
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
    if (!token) throw new Error('未登录，请先登录');

    const exp = getTokenExp(token);
    const now = Date.now();
    const refreshThreshold = 60 * 1000; // 剩余1分钟自动刷新

    if (exp && exp - now <= refreshThreshold) {
      try {
        await refreshAccessToken();
        token = localStorage.getItem('access-token'); // 刷新后拿新token
      } catch (err) {
        throw new Error('登录已过期，请重新登录');
      }
    }
  }

  const headers = {
    ...(options.headers || {}),
  };

  if (needsAuth && token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  try {
    const response = await fetch(`${path}`, {
      ...options,
      headers,
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({})); // 捕获 JSON 解析错误

      // 根据状态码返回统一的错误信息
      const errorMessage = {
        400: errorData.error || '请求无效，请检查输入内容',
        401: errorData.error || '未授权访问，请登录后重试',
        403: errorData.error || '您没有权限访问该资源',
        404: errorData.error || '请求的资源不存在',
        422: errorData.error || '请求无法处理，请检查输入内容',
        500: errorData.error || '服务器内部错误，请稍后重试',
      }[response.status] || errorData.message || '发生未知错误，请稍后重试';

      throw new Error(errorMessage);
    }

    if (response.status === 204 || !response.headers.get("Content-Type")) {
      return {}; // 处理空响应
    }

    if (response.headers.get("Content-Type")?.includes("application/json")) {
      return response.json();
    } else {
      return response; // 如果不是 JSON 响应，返回原始响应
    }
  } catch (err) {
    console.error(`请求失败: ${path}`, err);
    throw err; // 抛出错误以便调用方处理
  }
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
