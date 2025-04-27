
// 不需要token的路径
const TOKEN_WHITELIST = [
  '/api/login',
];

function getTokenExp(token) {
  if (!token) return null;
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.exp ? payload.exp * 1000 : null;
  } catch (e) {
    return null;
  }
}

async function refreshAccessToken() {
  const refreshToken = localStorage.getItem('client');
  if (!refreshToken) throw new Error('No refresh token');

  const response = await fetch('/api/refresh', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'client': refreshToken,
    },
  });

  if (response.ok) {
    const newAccessToken = response.headers.get('access-token');
    const newRefreshToken = response.headers.get('client');
    if (newAccessToken) localStorage.setItem('access-token', newAccessToken);
    if (newRefreshToken) localStorage.setItem('client', newRefreshToken);
  } else {
    throw new Error('Refresh token expired');
  }
}

async function apiFetch(path, options = {}) {
  const needsAuth = !TOKEN_WHITELIST.some((whitelistPath) => path.startsWith(whitelistPath));
  let token = localStorage.getItem('access-token');

  if (needsAuth) {
    if (!token) throw new Error('No access token');

    const exp = getTokenExp(token);
    const now = Date.now();
    const refreshThreshold = 60 * 1000; // 剩余1分钟自动刷新

    if (exp && exp - now <= refreshThreshold) {
      try {
        await refreshAccessToken();
        token = localStorage.getItem('access-token'); // 刷新后拿新token
      } catch (err) {
        throw err;
      }
    }
  }

  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };

  if (needsAuth && token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(`${path}`, {
    ...options,
    headers,
  });

  if (!response.ok) {
    if (response.status === 401 && needsAuth) {
      localStorage.clear();
      window.location.href = '/login?expired=1';
    }
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.message || 'API请求失败');
  }

  return response.json();
}

function startBackgroundRefresh() {
  stopBackgroundRefresh();

  window._refreshInterval = setInterval(async () => {
    const token = localStorage.getItem('access-token');
    if (!token) return;

    const exp = getTokenExp(token);
    const now = Date.now();
    const autoRefreshThreshold = 5 * 60 * 1000;

    if (exp && exp - now <= autoRefreshThreshold) {
      try {
        console.log('[后台刷新] 正在偷偷刷新...');
        await refreshAccessToken();
      } catch (err) {
        console.error('[后台刷新失败]', err);
      }
    }
  }, 2 * 60 * 1000);
}

function stopBackgroundRefresh() {
  if (window._refreshInterval) {
    clearInterval(window._refreshInterval);
    window._refreshInterval = null;
  }
}

export {
  apiFetch,
  startBackgroundRefresh,
  stopBackgroundRefresh,
};
