import {createBrowserRouter} from "react-router";
import ProtectedRoute from './ProtectedRoute'; 
import HomePage from "@/pages/HomePage";
import LoginPage from "@/pages/LoginPage";
import Page404 from "@/pages/Page404";
const router = createBrowserRouter([
  {
    path: "/",
    element: <ProtectedRoute />, // 受保护的路由
    children: [
      { path: "/", element: <HomePage /> }, // 子路由
    ],
  },
    {
      path: "/login",
      element: <LoginPage />,
    },
    {
      path: "*", // 捕获所有未匹配的路由
      element: <Page404 />, // 显示 404 页面
    },
  ]);

  export default router;