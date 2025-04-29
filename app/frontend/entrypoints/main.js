import React from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider } from "react-router";
import { AuthProvider } from '@/lib/providers/AuthProvider';
import router from '@/router'
import '@ant-design/v5-patch-for-react-19';
import 'antd/dist/reset.css';
document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('root')
  if (container) {
    const root = createRoot(container)
    root.render(<AuthProvider><RouterProvider router={router}/></AuthProvider>)
  }
})