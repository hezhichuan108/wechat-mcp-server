/**
 * HTTP Server for WeChat Official Account Publishing
 * Deploy on GitHub Codespaces for fixed IP.
 * 
 * Endpoints:
 *   POST /api/token        - Get access_token
 *   POST /api/upload-image - Upload image (multipart/form-data)
 *   POST /api/draft        - Add article to drafts
 *   POST /api/publish      - Publish draft article
 *   GET  /api/health       - Health check
 */

import http from 'node:http';
import { WeChatMP } from './wechat-api.js';
import { execSync } from 'node:child_process';

const PORT = Number(process.env.PORT) || 3000;
const AUTH_TOKEN = process.env.AUTH_TOKEN || '';  // Simple auth for API protection

// --- Auto-fetch WeChat credentials ---
// Priority: env vars > config.json > codespace secrets
async function getWeChatCredentials(): Promise<{ appId: string; appSecret: string }> {
  let appId = process.env.WECHAT_APP_ID || '';
  let appSecret = process.env.WECHAT_APP_SECRET || '';
  
  if (appId && appSecret) {
    console.log('✅ WeChat credentials loaded from environment variables');
    return { appId, appSecret };
  }
  
  // Try config.json (for Codespaces deployment)
  try {
    const fs = await import('node:fs');
    const path = await import('node:path');
    const configPath = path.resolve(process.cwd(), 'config.json');
    console.log(`🔍 Looking for config.json at: ${configPath}`);
    const configData = fs.readFileSync(configPath, 'utf-8');
    const config = JSON.parse(configData);
    appId = appId || config.WECHAT_APP_ID || '';
    appSecret = appSecret || config.WECHAT_APP_SECRET || '';
    if (appId && appSecret) {
      console.log('✅ WeChat credentials loaded from config.json');
      return { appId, appSecret };
    }
  } catch (e) {
    console.log(`⚠️ config.json not found or invalid: ${e}`);
  }
  
  console.warn('⚠️  WeChat credentials not configured!');
  return { appId, appSecret };
}

// Initialize credentials asynchronously
let wechatClient: WeChatMP;
let initPromise: Promise<void>;

async function init() {
  const creds = await getWeChatCredentials();
  wechatClient = new WeChatMP({
    appId: creds.appId,
    appSecret: creds.appSecret,
  });
  if (!creds.appId || !creds.appSecret) {
    console.warn('⚠️  WeChat credentials not configured! Set WECHAT_APP_ID and WECHAT_APP_SECRET');
  }
}
initPromise = init();

// --- Helpers ---

function parseBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

function json(res: http.ServerResponse, status: number, data: unknown) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(data));
}

function checkAuth(req: http.IncomingMessage, res: http.ServerResponse): boolean {
  if (!AUTH_TOKEN) return true;  // No auth configured, skip
  const token = req.headers['authorization']?.replace('Bearer ', '') || 
                new URL(req.url || '', `http://${req.headers.host}`).searchParams.get('token');
  if (token !== AUTH_TOKEN) {
    json(res, 401, { error: 'Unauthorized' });
    return false;
  }
  return true;
}

// --- Multipart parser for image upload ---

async function parseMultipart(req: http.IncomingMessage): Promise<{ filename: string; contentType: string; data: Buffer }> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
    req.on('end', () => {
      const fullBody = Buffer.concat(chunks);
      const contentType = req.headers['content-type'] || '';
      const boundaryMatch = contentType.match(/boundary=(.+)/);
      if (!boundaryMatch) return reject(new Error('No boundary found'));
      
      const boundary = boundaryMatch[1];
      const parts = fullBody.toString('binary').split(`--${boundary}`);
      
      for (const part of parts) {
        if (part.includes('Content-Disposition') && part.includes('filename=')) {
          const headerEnd = part.indexOf('\r\n\r\n');
          const header = part.substring(0, headerEnd);
          const body = part.substring(headerEnd + 4).replace(/\r\n--$/, '').replace(/\r\n$/, '');
          
          const filenameMatch = header.match(/filename="(.+?)"/);
          const ctMatch = header.match(/Content-Type:\s*(.+)/i);
          
          resolve({
            filename: filenameMatch?.[1] || 'upload.jpg',
            contentType: ctMatch?.[1].trim() || 'image/jpeg',
            data: Buffer.from(body, 'binary'),
          });
          return;
        }
      }
      reject(new Error('No file found in multipart'));
    });
    req.on('error', reject);
  });
}

// --- Routes ---

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '', `http://${req.headers.host}`);
  
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  try {
    await initPromise;  // Ensure credentials are loaded

    // Health check
    if (url.pathname === '/api/health' && req.method === 'GET') {
      json(res, 200, { status: 'ok', service: 'wechat-mp-publisher', time: new Date().toISOString() });
      return;
    }

    if (!checkAuth(req, res)) return;

    // Get access token
    if (url.pathname === '/api/token' && req.method === 'POST') {
      const token = await wechatClient.getAccessToken();
      json(res, 200, { access_token: token });
      return;
    }

    // Upload image
    if (url.pathname === '/api/upload-image' && req.method === 'POST') {
      const file = await parseMultipart(req);
      const token = await wechatClient.getAccessToken();
      
      // Build multipart for WeChat API
      const boundary = '----FormBoundary' + Math.random().toString(36).slice(2);
      const header = `------${boundary}\r\nContent-Disposition: form-data; name="media"; filename="${file.filename}"\r\nContent-Type: ${file.contentType}\r\n\r\n`;
      const footer = `\r\n------${boundary}--\r\n`;
      
      const body = Buffer.concat([
        Buffer.from(header, 'utf-8'),
        file.data,
        Buffer.from(footer, 'utf-8'),
      ]);

      const wxRes = await fetch(
        `https://api.weixin.qq.com/cgi-bin/material/add_material?access_token=${token}&type=image`,
        {
          method: 'POST',
          headers: { 'Content-Type': `multipart/form-data; boundary=----${boundary}` },
          body,
        }
      );
      const wxData = await wxRes.json() as Record<string, unknown>;
      
      if (wxData.media_id || wxData.url) {
        json(res, 200, wxData);
      } else {
        json(res, 400, { error: 'Upload failed', detail: wxData });
      }
      return;
    }

    // Add draft
    if (url.pathname === '/api/draft' && req.method === 'POST') {
      const body = await parseBody(req);
      const { title, content, thumb_media_id, author, digest } = JSON.parse(body);
      
      if (!title || !content || !thumb_media_id) {
        json(res, 400, { error: 'Missing required fields: title, content, thumb_media_id' });
        return;
      }
      
      const result = await wechatClient.addDraft([{
        title,
        content,
        thumb_media_id,
        author: author || '',
        digest: digest || '',
      }]);
      
      json(res, 200, result);
      return;
    }

    // Publish
    if (url.pathname === '/api/publish' && req.method === 'POST') {
      const body = await parseBody(req);
      const { media_id } = JSON.parse(body);
      
      if (!media_id) {
        json(res, 400, { error: 'Missing required field: media_id' });
        return;
      }
      
      const result = await wechatClient.publish(media_id);
      json(res, 200, result);
      return;
    }

    // 404
    json(res, 404, { error: 'Not found' });
    
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[${new Date().toISOString()}] Error:`, msg);
    json(res, 500, { error: msg });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 WeChat MP Publisher HTTP Server running on port ${PORT}`);
  console.log(`   Health: http://localhost:${PORT}/api/health`);
  console.log(`   Auth: ${AUTH_TOKEN ? 'enabled' : 'disabled (set AUTH_TOKEN to protect)'}`);
});
