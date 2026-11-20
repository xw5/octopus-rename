{ 应用版本号 —— 全项目唯一版本来源。
  build.bat 解析 APP_VERSION 所在行，自动生成 VERSIONINFO 资源并注入 manifest；
  窗口标题（unit1.pas）直接引用 APP_VERSION 常量。发布新版本只改这一行。
  注意：APP_VERSION 行必须顶格书写（build.bat 的 findstr /b 按行首匹配）。}
const
APP_VERSION = '1.0.2';
