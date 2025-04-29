import React from 'react';
import { Outlet, Navigate } from 'react-router';
import { useAuth } from '@/lib/hooks/useAuth';

function ProtectedRoute() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh' }}>
        <p>加载中...</p>
      </div>
    );
  }

  if (!user?.loggedIn) {
    const currentPath = window.location.pathname;
    if (currentPath !== '/login') {
      localStorage.setItem('redirectAfterLogin', currentPath);
    }
    return <Navigate to="/login" />;
  }
  return <Outlet  context={{ user }} />; // 渲染子路由
}

export default ProtectedRoute;