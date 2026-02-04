import React from 'react';
import { useMsal, useIsAuthenticated } from '@azure/msal-react';
import { loginRequest } from '../authConfig';

function SignInButton() {
  const { instance, accounts } = useMsal();
  const isAuthenticated = useIsAuthenticated();

  const handleLogin = () => {
    instance.loginRedirect(loginRequest).catch((e) => {
      console.error('Login failed:', e);
    });
  };

  const handleLogout = () => {
    instance.logoutRedirect().catch((e) => {
      console.error('Logout failed:', e);
    });
  };

  if (isAuthenticated) {
    const name = accounts[0]?.name || accounts[0]?.username || 'User';
    return (
      <div className="auth-controls">
        <span className="auth-user">{name}</span>
        <button className="auth-button auth-signout" onClick={handleLogout}>
          Sign Out
        </button>
      </div>
    );
  }

  return (
    <button className="auth-button auth-signin" onClick={handleLogin}>
      Sign In
    </button>
  );
}

export default SignInButton;
