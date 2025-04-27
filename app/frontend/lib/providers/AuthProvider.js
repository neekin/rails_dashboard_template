import React, { createContext, useState, useEffect } from 'react';
import { apiFetch, startBackgroundRefresh, stopBackgroundRefresh } from '../api/fetch';

const AuthContext = createContext();

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true); // 添加 loading 状态

  const fetchUser = async () => {
    try {
      const response = await apiFetch('/api/profile');
      setUser({ ...response.user, loggedIn: true });
      startBackgroundRefresh();
    } catch (err) {
      console.error('获取用户信息失败', err);
      logout();
    } finally {
      setLoading(false); // 加载完成
    }
  };

  useEffect(() => {
    const token = localStorage.getItem('access-token');
    if (token) {
      fetchUser();
    } else {
      setLoading(false); // 如果没有 token，直接完成加载
    }
  }, []);

  const login = async () => {
    await fetchUser();
  };

  const logout = () => {
    setUser(null);
    stopBackgroundRefresh();
    localStorage.clear();
    window.location.href = '/login';
  };

  return (
    <AuthContext.Provider value={{ user, loading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export default AuthContext;
