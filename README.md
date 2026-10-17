# TranMac

菜单栏翻译小工具：`⌃;` 呼出/隐藏输入框，中文 → 英文，其它语言 → 简体中文。

翻译服务可在菜单栏「设置…」（`⌘,`）中切换：

- **系统翻译**（默认）：macOS 26 自带 Translation 框架，离线、本地运行
- **LLM API**：任意 OpenAI 兼容的 `/chat/completions` 接口（OpenAI、DeepSeek、通义千问、OpenRouter、Ollama 等），填写 Base URL、API Key、模型即可，流式输出

- `↩` 复制译文并关闭，`⎋` 关闭，点其它地方自动关闭
- 首次使用某个语言方向时，面板里点「下载语言包」下载离线模型
- 菜单栏图标可打开设置、设置开机启动、退出

构建：

```bash
./build.sh            # 生成 build/TranMac.app
./build.sh --install  # 安装到 /Applications 并启动
```
# TranMac
