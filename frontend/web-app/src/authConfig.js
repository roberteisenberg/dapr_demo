import { PublicClientApplication, LogLevel } from '@azure/msal-browser';

// Read from runtime config (window.__CONFIG__ set by public/config.js or K8s ConfigMap)
const config = window.__CONFIG__ || {};

const clientId = config.AZURE_CLIENT_ID || '';
const tenantId = config.AZURE_TENANT_ID || '';

// Auth is enabled only when both values are provided
export const authEnabled = Boolean(clientId && tenantId);

const msalConfig = {
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
  system: {
    loggerOptions: {
      loggerCallback: (level, message, containsPii) => {
        if (containsPii) return;
        if (level === LogLevel.Error) {
          console.error('[MSAL]', message);
        }
      },
      logLevel: LogLevel.Error,
    },
  },
};

// Login request scopes
export const loginRequest = {
  scopes: clientId ? [`api://${clientId}/access_as_user`] : [],
};

// Token request for API calls
export const tokenRequest = {
  scopes: clientId ? [`api://${clientId}/access_as_user`] : [],
};

// Create MSAL instance (only used when auth is enabled)
let _msalInstance = null;
if (authEnabled) {
  try {
    _msalInstance = new PublicClientApplication(msalConfig);
  } catch (err) {
    console.error('[MSAL] Failed to create instance:', err);
  }
}
export const msalInstance = _msalInstance;
