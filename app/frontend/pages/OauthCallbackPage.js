// filepath: app/frontend/pages/OAuthCallbackPage.js
import React, { useEffect, useContext } from 'react';
import { useLocation, useNavigate } from 'react-router';
import { Spin, message, Alert } from 'antd';
import { useAuth } from '@/lib/hooks/useAuth'; // Assuming useAuth provides login function and sets tokens
import { apiFetch } from '@/lib/api/fetch'; // Your configured axios instance

const OAuthCallbackPage = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const { login } = useAuth(); // login(userData) should set user in context

  useEffect(() => {
    const params = new URLSearchParams(location.search);
    const accessToken = params.get('access_token');
    const clientToken = params.get('client'); // This is the refresh token
    // const uid = params.get('uid'); // User ID

    if (accessToken && clientToken) {
      localStorage.setItem('access-token', accessToken);
      localStorage.setItem('client', clientToken); // Store refresh token

      // After storing tokens, fetch user details from /api/v1/me
      apiFetch('/api/me') // apiClient should automatically include the 'access-token' header
        .then(response => {
          if (response) {
            login(response); // Update auth context with user data
            message.success('登录成功！');
            const redirectPath = localStorage.getItem('redirectAfterLogin') || '/';
            localStorage.removeItem('redirectAfterLogin');
            navigate(redirectPath);
          } else {
            throw new Error('未能获取用户信息');
          }
        })
        .catch(err => {
          message.error(err.message || '通过 OAuth 登录失败，无法获取用户信息。');
          localStorage.removeItem('access-token');
          localStorage.removeItem('client');
          navigate('/login');
        });
    } else {
      const error = params.get('error');
      const errorMessage = params.get('message') || 'OAuth 认证失败，缺少令牌。';
      message.error(`登录失败: ${errorMessage}`);
      navigate('/login');
    }
  }, [location, navigate, login]);

  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh' }}>
      <Spin size="large" tip="正在处理登录..." />
    </div>
  );
};

export default OAuthCallbackPage;