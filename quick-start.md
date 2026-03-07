# 快速开始指南

## 立即使用（5分钟部署）

### 选项1：GitHub Codespaces（推荐）

1. **Fork这个仓库**
   - 点击GitHub页面右上角的"Fork"按钮

2. **配置Secrets**
   ```
   Settings → Secrets and variables → Actions → New repository secret
   - Name: WECHAT_APP_ID
   - Value: 你的微信公众号AppID
   
   - Name: WECHAT_APP_SECRET  
   - Value: 你的微信公众号AppSecret
   ```

3. **启动Codespaces**
   ```
   Code → Codespaces → Create codespace on main
   ```

4. **验证部署**
   ```bash
   # 在Codespaces终端中运行
   mcporter list
   mcporter call wechat-mp.get_access_token
   ```

### 选项2：本地运行

```bash
# 克隆仓库
git clone https://github.com/YOUR_USERNAME/mcp-wechat-publisher.git
cd mcp-wechat-publisher

# 安装依赖
npm install

# 编译
npm run build

# 设置环境变量
export WECHAT_APP_ID="你的AppID"
export WECHAT_APP_SECRET="你的AppSecret"

# 测试
node dist/index.js
```

## 小微的第一次发布

### 步骤1：准备文章

```json
{
  "title": "我的第一篇自动化文章",
  "content": "<h1>标题</h1><p>这是内容...</p>",
  "thumb_media_id": "封面图片ID"
}
```

### 步骤2：调用MCP

```bash
# 添加草稿
mcporter call wechat-mp.add_draft \
  title="我的第一篇自动化文章" \
  content="<h1>标题</h1><p>这是内容...</p>" \
  thumb_media_id="YOUR_COVER_IMAGE_ID"
  
# 记录返回的media_id

# 发布
mcporter call wechat-mp.publish media_id="RETURNED_MEDIA_ID"
```

## 常见问题

**Q: 没有固定IP怎么办？**
A: 使用GitHub Codespaces，它提供固定的公网IP地址。

**Q: 如何上传封面图片？**
A: 暂时需要手动上传到微信公众号后台，获取media_id后使用。

**Q: 发布失败怎么办？**
A: 检查access_token是否有效，确认文章格式正确。

**Q: 可以定时发布吗？**
A: 可以结合GitHub Actions实现定时发布功能。

## 下一步

- ✅ 部署MCP Server
- ✅ 测试发布流程
- 📝 编写自动化脚本
- 🔄 集成到小微的工作流
