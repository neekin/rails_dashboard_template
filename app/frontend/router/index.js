import { createBrowserRouter } from "react-router";
import ProtectedRoute from "./ProtectedRoute";
import HomePage from "@/pages/HomePage";
import LoginPage from "@/pages/LoginPage";
import Page404 from "@/pages/Page404";
// import AdminLayout from "@/components/AdminLayout";
import AdminLayout from "@/components/pro/AdminLayout";
import DynamicTablePage from "@/pages/DynamicTablePage";
import DynamicFieldPage from "@/pages/DynamicFieldPage";
import DynamicDataPage from "@/pages/DynamicDataPage";
import AppEntityPage from "@/pages/AppEntityPage";
const router = createBrowserRouter([
  {
    path: "/admin",
    element: <ProtectedRoute />, // 受保护的路由
    children: [
      {
        path: "",
        element: <AdminLayout />,
        children: [
          {
            path: "apps",
            element: <AppEntityPage />,
          },
          {
            path: "dynamic_tables/:appId",
            element: <DynamicTablePage />,
          },
          {
            path: "dynamic_fields/:tableId",
            element: <DynamicFieldPage />,
          },
          {
            path: "dynamic_records/:tableId",
            element: <DynamicDataPage />,
          },
          { path: "", element: <HomePage /> },

        ],
      },
    ],
  },
  {
    path: "/login",
    element: <LoginPage />,
  },

  {
    path: "/login1",
    element: <LoginPage />,
  },
  {
    path: "*", // 捕获所有未匹配的路由
    element: <Page404 />, // 显示 404 页面
  },
]);

export default router;
