#!/usr/bin/env python3
"""
在 Codespaces 中运行的微信公众号文章下载脚本
"""

import requests
import json
import time
import os
import re

# 公众号凭证
APP_ID = "wxb2894500c4bf769b"
APP_SECRET = "459877c145acc2173f4ffb053bcc7153"

# 输出目录
OUTPUT_DIR = "/workspaces/wechat-mcp-server/WeChat_Articles"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def get_access_token():
    """获取 access_token"""
    url = f"https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid={APP_ID}&secret={APP_SECRET}"
    resp = requests.get(url, timeout=10)
    resp.encoding = 'utf-8'
    data = resp.json()
    
    if 'access_token' in data:
        print(f"✅ 获取 access_token 成功")
        return data['access_token']
    else:
        print(f"❌ 获取 access_token 失败: {data}")
        return None

def get_material_list(access_token, material_type="news", offset=0, count=20):
    """获取素材列表"""
    url = f"https://api.weixin.qq.com/cgi-bin/material/batchget_material?access_token={access_token}"
    
    payload = {
        "type": material_type,
        "offset": offset,
        "count": count
    }
    
    resp = requests.post(url, json=payload, timeout=30)
    resp.encoding = 'utf-8'
    data = resp.json()
    
    if 'item' in data:
        return data
    else:
        print(f"❌ 获取素材列表失败: {data}")
        return None

def download_image(url, output_dir):
    """下载图片"""
    try:
        resp = requests.get(url, timeout=30)
        if resp.status_code == 200:
            filename = os.path.basename(url.split('?')[0])
            if not filename or '.' not in filename:
                filename = f"image_{int(time.time())}.jpg"
            
            filepath = os.path.join(output_dir, filename)
            with open(filepath, 'wb') as f:
                f.write(resp.content)
            return filename
    except Exception as e:
        print(f"    ⚠️  图片下载失败: {e}")
    return None

def extract_images_from_content(content):
    """从 HTML 内容中提取图片 URL"""
    pattern = r'data-src="(https://mmbiz\.qpic\.cn/[^"]+)"|src="(https://mmbiz\.qpic\.cn/[^"]+)"'
    matches = re.findall(pattern, content)
    
    images = []
    for match in matches:
        url = match[0] if match[0] else match[1]
        if url:
            images.append(url)
    
    return images

def sanitize_filename(text, max_length=50):
    """清理文件名"""
    if not text:
        return "untitled"
    
    text = re.sub(r'[\\/*?:"<>|]', '', text)
    text = text.strip()
    
    if len(text) > max_length:
        text = text[:max_length]
    
    if not text:
        text = "untitled"
    
    return text

def save_article(article, index, total):
    """保存单篇文章"""
    title = article.get('title', '无标题')
    author = article.get('author', '')
    content = article.get('content', '')
    url = article.get('url', '')
    digest = article.get('digest', '')
    
    safe_title = sanitize_filename(title)
    
    article_dir = os.path.join(OUTPUT_DIR, f"{index:03d}_{safe_title}")
    os.makedirs(article_dir, exist_ok=True)
    
    print(f"\n[{index}/{total}] {title}")
    print(f"  作者: {author}")
    
    images = extract_images_from_content(content)
    print(f"  发现 {len(images)} 张图片")
    
    downloaded_images = []
    for i, img_url in enumerate(images):
        print(f"    下载图片 {i+1}/{len(images)}...", end=' ')
        filename = download_image(img_url, article_dir)
        if filename:
            downloaded_images.append(filename)
            print(f"✅")
        else:
            print(f"❌")
        time.sleep(0.3)
    
    modified_content = content
    for img_url in images:
        filename = os.path.basename(img_url.split('?')[0])
        if filename:
            modified_content = modified_content.replace(f'data-src="{img_url}"', f'src="{filename}"')
            modified_content = modified_content.replace(f'src="{img_url}"', f'src="{filename}"')
    
    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>{title}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Microsoft YaHei', sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }}
        h1 {{ color: #333; border-bottom: 2px solid #eee; padding-bottom: 10px; }}
        .meta {{ color: #666; margin-bottom: 20px; }}
        img {{ max-width: 100%; height: auto; }}
        .content {{ margin-top: 30px; }}
    </style>
</head>
<body>
    <h1>{title}</h1>
    <div class="meta">
        <p>作者: {author}</p>
        <p>原文链接: <a href="{url}">{url}</a></p>
    </div>
    <div class="content">
        {modified_content}
    </div>
</body>
</html>"""
    
    html_path = os.path.join(article_dir, "index.html")
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    if digest:
        digest_path = os.path.join(article_dir, "digest.txt")
        with open(digest_path, 'w', encoding='utf-8') as f:
            f.write(digest)
    
    print(f"  ✅ 文章已保存")
    
    return {
        'title': title,
        'author': author,
        'url': url,
        'directory': article_dir,
        'images_count': len(downloaded_images),
        'images': downloaded_images
    }

def generate_index(downloaded):
    """生成索引文件"""
    print("\n" + "=" * 60)
    print("📋 生成索引文件...")
    
    index_html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>微信公众号文章索引</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Microsoft YaHei', sans-serif; max-width: 1000px; margin: 0 auto; padding: 20px; }}
        h1 {{ color: #333; border-bottom: 2px solid #07c160; padding-bottom: 10px; }}
        .article {{ margin: 20px 0; padding: 15px; border: 1px solid #eee; border-radius: 8px; }}
        .article:hover {{ background: #f9f9f9; }}
        .title {{ font-size: 18px; font-weight: bold; color: #07c160; }}
        .meta {{ color: #666; margin-top: 5px; }}
        .link {{ margin-top: 10px; }}
        .link a {{ color: #576b95; text-decoration: none; }}
        .link a:hover {{ text-decoration: underline; }}
    </style>
</head>
<body>
    <h1>微信公众号文章索引</h1>
    <p>共 {len(downloaded)} 篇文章</p>
"""
    
    for art in downloaded:
        index_html += f"""
    <div class="article">
        <div class="title">{art['title']}</div>
        <div class="meta">作者: {art['author']} | 图片: {art['images_count']} 张</div>
        <div class="link"><a href="{os.path.basename(art['directory'])}/index.html">查看文章</a></div>
    </div>"""
    
    index_html += """
</body>
</html>"""
    
    index_path = os.path.join(OUTPUT_DIR, "index.html")
    with open(index_path, 'w', encoding='utf-8') as f:
        f.write(index_html)
    
    print(f"✅ 索引文件已生成: {index_path}")

def main():
    print("=" * 60)
    print("  微信公众号文章批量下载工具 (Codespaces)")
    print("=" * 60)
    print()
    
    # 获取当前 IP
    try:
        ip = requests.get("https://ifconfig.me", timeout=10).text.strip()
        print(f"🌐 当前 Codespaces IP: {ip}")
        print()
    except:
        pass
    
    access_token = get_access_token()
    if not access_token:
        print("无法获取 access_token，退出")
        return 1
    
    print()
    print("📥 获取文章列表...")
    
    all_articles = []
    offset = 0
    count = 20
    total_count = 0
    
    while True:
        data = get_material_list(access_token, "news", offset, count)
        if not data or 'item' not in data:
            break
        
        items = data['item']
        if not items:
            break
        
        total_count = data.get('total_count', 0)
        
        for item in items:
            if '