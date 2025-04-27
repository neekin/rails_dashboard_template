import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [
    react({
      jsxImportSource: '@emotion/react', // 或者 'react'
      jsxRuntime: 'automatic', // 或者 'classic'
      // 可以移除这里的 include，让 esbuild 配置接管
    }),
    RubyPlugin(),
  ],
  resolve: {
    extensions: ['.js', '.jsx', '.ts', '.tsx'],
  },
  // 明确告诉 esbuild 如何处理 .js 文件
  esbuild: {
    loader: 'jsx', // 将 jsx 作为默认 loader
    // 关键：确保 include 匹配你包含 JSX 的 .js 文件路径
    // 这个正则表达式匹配 app/frontend/ 下的所有 .js 和 .jsx 文件
    include: /app\/frontend\/.*\.(js|jsx)$/,
    exclude: [],
  },
  // 可选：为依赖优化也指定 loader
  optimizeDeps: {
    esbuildOptions: {
      loader: {
        '.js': 'jsx',
      },
    },
  },
})