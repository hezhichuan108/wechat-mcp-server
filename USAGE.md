# 微信公众号自动化发布使用指南

## 快速开始

### 第一步：部署到GitHub Codespaces

1. **创建GitHub仓库**
   ```bash
   # 在GitHub上创建新仓库：mcp-wechat-publisher
   # 将本地代码推送上去
   git init
   git add .
   git commit -m "Initial commit: MCP WeChat Publisher"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/mcp-wechat-publisher.git
   git push -u origin main
   ```

2. **配置GitHub Secrets**
   - 进入仓库Settings → Secrets and variables → Actions
   - 添加以下secrets：
     - `WECHAT_APP_ID`: 你的微信公众号AppID
     - `WECHAT_APP_SECRET`: 你的微信公众号AppSecret

3. **启动Codespaces**
   - 在GitHub仓库页面点击"Code" → "Codespaces" → "Create codespace on main"
   - 等待环境自动配置（约2-3分钟）

### 第二步：本地配置MCP客户端

1. **安装mcporter**
   ```bash
   npm install -g mcporter
   ```

2. **配置MCP服务器连接**
   ```bash
   # 在Codespaces终端中运行
   mcporter config add wechat-mp --stdio "node dist/index.js"
   ```

3. **设置环境变量**
   ```bash
   # Windows PowerShell
   $env:WECHAT_APP_ID="你的AppID"
   $env:WECHAT_APP_SECRET="你的AppSecret"
   
   # Linux/Mac
   export WECHAT_APP_ID="你的AppID"
   export WECHAT_APP_SECRET="你的AppSecret"
   ```

### 第三步：使用MCP工具发布文章

#### 1. 获取access_token
```bash
mcporter call wechat-mp.get_access_token
```

#### 2. 添加草稿
```bash
mcporter call wechat-mp.add_draft \
  title="文章标题" \
  content="<html><body><h1>文章内容</h1></body></html>" \
  thumb_media_id="封面图片的media_id"
```

#### 3. 发布草稿
```bash
mcporter call wechat-mp.publish media_id="草稿的media_id"
```

## 小微的使用流程

### 自动化发布工作流

小微可以按照以下流程自动化发布文章：

```bash
# 1. 准备文章内容
article_title="最新技术研究成果"
article_content="<h1>研究概述</h1><p>详细内容...</p>"
cover_image_id="xxx"  # 需要先上传封面图片

# 2. 添加到草稿箱
draft_result=$(mcporter call wechat-mp.add_draft \
  title="$article_title" \
  content="$article_content" \
  thumb_media_id="$cover_image_id")

# 3. 提取media_id
media_id=$(echo $draft_result | jq -r '.media_id')

# 4. 发布
mcporter call wechat-mp.publish media_id="$media_id"
```

### 一键发布脚本

创建发布脚本 `publish-article.sh`：

```bash
#!/bin/bash

# 文章信息
TITLE="$1"
CONTENT="$2"
COVER_ID="$3"

if [ -z "$TITLE" ] || [ -z "$CONTENT" ] || [ -z "$COVER_ID" ]; then
  echo "Usage: ./publish-article.sh <title> <content> <cover_media_id>"
  exit 1
fi

echo "正在发布文章: $TITLE"

# 添加草稿
DRAFT_RESULT=$(mcporter call wechat-mp.add_draft \
  title="$TITLE" \
  content="$CONTENT" \
  thumb_media_id="$COVER_ID")

# 提取media_id
MEDIA_ID=$(echo "$DRAFT_RESULT" | jq -r '.media_id')

if [ -z "$MEDIA_ID" ] || [ "$MEDIA_ID" = "null" ]; then
  echo "错误: 无法创建草稿"
  echo "$DRAFT_RESULT"
  exit 1
fi

echo "草稿已创建: $MEDIA_ID"

# 发布
PUBLISH_RESULT=$(mcporter call wechat-mp.publish media_id="$MEDIA_ID")

echo "发布结果:"
echo "$PUBLISH_RESULT"
```

## 注意事项

### 微信公众号API限制

1. **封面图片**：必须先上传到微信服务器获取media_id
2. **发布频率**：每天最多发布1次
3. **文章格式**：content字段必须是HTML格式
4. **审核流程**：部分账号需要审核后才能发布

### 安全建议

1. **不要硬编码密钥**：始终使用环境变量
2. **定期更换密钥**：建议每月更换AppSecret
3. **限制权限**：只在需要时授予发布权限
4. **日志记录**：记录所有发布操作以便追溯

### 错误处理

常见错误及解决方案：

| 错误码 | 说明 | 解决方案 |
|--------|------|----------|
| 40001 | AppSecret错误 | 检查环境变量配置 |
| 40014 | access_token无效 | 重新获取token |
| 45008 | 超过文章数量限制 | 删除旧文章后重试 |
| 40125 | 无效的media_id | 重新上传封面图片 |

## 扩展功能

### 图片上传工具

可以扩展MCP Server添加图片上传功能：

```typescript
// 在wechat-api.ts中添加
async uploadImage(imageUrl: string): Promise<string> {
  const token = await this.getAccessToken();
  // 下载图片
  const imageResponse = await fetch(imageUrl);
  const imageBuffer = await imageResponse.arrayBuffer();
  
  // 上传到微信
  const formData = new FormData();
  formData.append('media', new Blob([imageBuffer]), 'image.jpg');
  
  const url = `${WECHAT_API_BASE}/material/add_material?access_token=${token}&type=image`;
  const response = await fetch(url, {
    method: 'POST',
    body: formData
  });
  
  const data = await response.json();
  return data.media_id;
}
```

### 文章模板

创建文章模板生成器：

```typescript
function generateArticleTemplate(title: string, content: string, author: string): string {
  return `
    <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; padding: 20px; }
          h1 { color: #333; }
          p { line-height: 1.6; }
        </style>
      </head>
      <body>
        <h1>${title}</h1>
        <p><small>作者: ${author}</small></p>
        <div>${content}</div>
      </body>
    </html>
  `;
}
```

## 联系支持

如遇问题，请联系：
- 技术支持：小助理
- 使用指导：小微
