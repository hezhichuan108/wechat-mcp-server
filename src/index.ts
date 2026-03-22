#!/usr/bin/env node

/**
 * MCP Server for WeChat Official Account Article Publishing
 * 
 * This server provides tools to publish articles to WeChat Official Account
 * via the Model Context Protocol (MCP).
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ErrorCode,
  McpError,
} from "@modelcontextprotocol/sdk/types.js";
import { WeChatMP, Article } from "./wechat-api.js";

// Get WeChat credentials from environment
const WECHAT_APP_ID = process.env.WECHAT_APP_ID;
const WECHAT_APP_SECRET = process.env.WECHAT_APP_SECRET;

if (!WECHAT_APP_ID || !WECHAT_APP_SECRET) {
  console.error("Error: WECHAT_APP_ID and WECHAT_APP_SECRET environment variables are required");
  process.exit(1);
}

// Initialize WeChat client
const wechatClient = new WeChatMP({
  appId: WECHAT_APP_ID,
  appSecret: WECHAT_APP_SECRET
});

// Create MCP server
const server = new Server(
  {
    name: "wechat-mp-publisher",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

/**
 * Handler for listing available tools
 */
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "get_access_token",
        description: "获取微信access_token",
        inputSchema: {
          type: "object",
          properties: {},
        },
      },
      {
        name: "add_draft",
        description: "添加文章到草稿箱",
        inputSchema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "文章标题",
            },
            author: {
              type: "string",
              description: "作者",
            },
            content: {
              type: "string",
              description: "文章内容（HTML格式）",
            },
            digest: {
              type: "string",
              description: "摘要",
            },
            thumb_media_id: {
              type: "string",
              description: "封面图片的media_id",
            },
          },
          required: ["title", "content", "thumb_media_id"],
        },
      },
      {
        name: "publish",
        description: "发布草稿文章",
        inputSchema: {
          type: "object",
          properties: {
            media_id: {
              type: "string",
              description: "草稿的media_id",
            },
          },
          required: ["media_id"],
        },
      },
    ],
  };
});

/**
 * Handler for tool execution
 */
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "get_access_token": {
        const token = await wechatClient.getAccessToken();
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ access_token: token }, null, 2),
            },
          ],
        };
      }

      case "add_draft": {
        const article: Article = {
          title: args.title as string,
          author: args.author as string | undefined,
          content: args.content as string,
          digest: args.digest as string | undefined,
          thumb_media_id: args.thumb_media_id as string,
        };

        const result = await wechatClient.addDraft([article]);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      case "publish": {
        const mediaId = args.media_id as string;
        const result = await wechatClient.publish(mediaId);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      default:
        throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Error: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
});

/**
 * Start the server
 */
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("WeChat MP MCP Server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error in main():", error);
  process.exit(1);
});
