# MCP + GitHub Codespaces 微信公众号自动化发布方案

## 方案概述

使用GitHub Codespaces作为免费服务器，部署MCP Server包装微信公众号API，实现一键发布文章。

## 架构设计

```
本地环境 → MCP Client (mcporter) → GitHub Codespaces (MCP Server) → 微信公众号API
```

## 优势

1. **完全免费**：GitHub Codespaces每月60小时免费额度
2. **固定IP**：Codespaces提供稳定的访问地址
3. **无需本地服务器**：所有服务托管在云端
4. **易于维护**：代码化管理，版本控制

## 实施步骤

### 第一步：创建GitHub仓库

```bash
# 创建新仓库
mkdir mcp-wechat-publisher
cd mcp-wechat-publisher
git init
```

### 第二步：配置GitHub Codespaces

创建 `.devcontainer/devcontainer.json`：

```json
{
  "name": "MCP WeChat Publisher",
  "image": "mcr.microsoft.com/devcontainers/javascript-node:20",
  "features": {
    "ghcr.io/devcontainers/features/node:1": {}
  },
  "postCreateCommand": "npm install",
  "forwardPorts": [3000],
  "customizations": {
    "vscode": {
      "extensions": ["ms-vscode-remote.remote-containers"]
    }
  }
}
```

### 第三步：创建MCP Server

创建 `server/index.ts`：

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

// 微信公众号API工具
const wechatTools = {
  name: "wechat-mp",
  description: "微信公众号文章发布工具",
  tools: [
    {
      name: "publish_draft",
      description: "发布文章到草稿箱",
      inputSchema: {
        type: "object",
        properties: {
          title: { type: "string" },
          content: { type: "string" },
          thumb_media_id: { type: "string" }
        }
      }
    },
    {
      name: "get_access_token",
      description: "获取微信access_token",
      inputSchema: {
        type: "object",
        properties: {
          appid: { type: "string" },
          secret: { type: "string" }
        }
      }
    }
  ]
};

// 实现MCP Server
const server = new Server(
  { name: "wechat-mp-server", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// 注册工具处理器
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: wechatTools.tools };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  // 实现工具调用逻辑
});

// 启动服务器
const transport = new StdioServerTransport();
await server.connect(transport);
```

### 第四步：配置微信公众号API

创建 `src/wechat-api.ts`：

```typescript
const WECHAT_API = 'https://api.weixin.qq.com/cgi-bin';

export class WeChatMP {
  private appId: string;
  private appSecret: string;
  private accessToken: string;

  constructor(appId: string, appSecret: string) {
    this.appId = appId;
    this.appSecret = appSecret;
  }

  async getAccessToken() {
    const url = `${WECHAT_API}/token?grant_type=client_credential&appid=${this.appId}&secret=${this.appSecret}`;
    const response = await fetch(url);
    const data = await response.json();
    this.accessToken = data.access_token;
    return this.accessToken;
  }

  async addDraft(articles: any[]) {
    const url = `${WECHAT_API}/draft/add?access_token=${this.accessToken}`;
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ articles })
    });
    return await response.json();
  }
}
```

### 第五步：配置package.json

```json
{
  "name": "mcp-wechat-publisher",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "node server/index.js",
    "dev": "tsx watch server/index.ts"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0"
  }
}
```

### 第六步：本地调用

在本地环境使用mcporter调用：

```bash
# 配置MCP服务器
mcporter config add wechat-mp --stdio "node dist/index.js"

# 调用发布工具
mcporter call wechat-mp.publish_draft \
  title="文章标题" \
  content="文章内容HTML"
```

## 安全配置

1. **环境变量**：微信公众号AppID和Secret存储在GitHub Secrets中
2. **访问控制**：Codespaces仅允许授权用户访问
3. **Token管理**：access_token缓存和自动刷新

## 成本估算

- **GitHub Codespaces**：免费60小时/月
- **微信公众号API**：免费调用
- **总成本**：**¥0**

## 下一步行动

1. 创建GitHub仓库
2. 配置Codespaces环境
3. 部署MCP Server
4. 测试发布流程
5. 编写使用文档
