/**
 * WeChat Official Account API Client
 */

const WECHAT_API_BASE = 'https://api.weixin.qq.com/cgi-bin';

export interface WeChatConfig {
  appId: string;
  appSecret: string;
}

export interface AccessToken {
  access_token: string;
  expires_in: number;
}

export interface Article {
  title: string;
  author?: string;
  digest?: string;
  content: string;
  content_source_url?: string;
  thumb_media_id: string;
  need_open_comment?: number;
  only_fans_can_comment?: number;
}

export class WeChatMP {
  private appId: string;
  private appSecret: string;
  private accessToken: string | null = null;
  private tokenExpiry: number = 0;

  constructor(config: WeChatConfig) {
    this.appId = config.appId;
    this.appSecret = config.appSecret;
  }

  /**
   * Get access token
   */
  async getAccessToken(): Promise<string> {
    // Check if token is still valid
    if (this.accessToken && Date.now() < this.tokenExpiry) {
      return this.accessToken;
    }

    const url = `${WECHAT_API_BASE}/token?grant_type=client_credential&appid=${this.appId}&secret=${this.appSecret}`;
    
    try {
      const response = await fetch(url);
      const data = await response.json() as AccessToken;
      
      if (data.access_token) {
        this.accessToken = data.access_token;
        // Set expiry 5 minutes before actual expiry
        this.tokenExpiry = Date.now() + (data.expires_in - 300) * 1000;
        return this.accessToken;
      } else {
        throw new Error(`Failed to get access token: ${JSON.stringify(data)}`);
      }
    } catch (error) {
      throw new Error(`Error fetching access token: ${error}`);
    }
  }

  /**
   * Upload image to get media_id
   */
  async uploadImage(imagePath: string): Promise<string> {
    const token = await this.getAccessToken();
    const url = `${WECHAT_API_BASE}/material/add_material?access_token=${token}&type=image`;
    
    // TODO: Implement image upload
    throw new Error('Image upload not implemented yet');
  }

  /**
   * Add draft article
   */
  async addDraft(articles: Article[]): Promise<{ media_id: string }> {
    const token = await this.getAccessToken();
    const url = `${WECHAT_API_BASE}/draft/add?access_token=${token}`;
    
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ articles })
      });
      
      const data = await response.json() as { media_id?: string; errcode?: number; errmsg?: string };
      
      if (data.media_id) {
        return { media_id: data.media_id };
      } else {
        throw new Error(`Failed to add draft: ${JSON.stringify(data)}`);
      }
    } catch (error) {
      throw new Error(`Error adding draft: ${error}`);
    }
  }

  /**
   * Publish article
   */
  async publish(mediaId: string): Promise<{ publish_id: string; msg_data_id: string }> {
    const token = await this.getAccessToken();
    const url = `${WECHAT_API_BASE}/freepublish/submit?access_token=${token}`;
    
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ media_id: mediaId })
      });
      
      const data = await response.json() as { publish_id?: string; msg_data_id?: string; errcode?: number; errmsg?: string };
      
      if (data.publish_id) {
        return { 
          publish_id: data.publish_id, 
          msg_data_id: data.msg_data_id || '' 
        };
      } else {
        throw new Error(`Failed to publish: ${JSON.stringify(data)}`);
      }
    } catch (error) {
      throw new Error(`Error publishing: ${error}`);
    }
  }
}
