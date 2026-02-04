import React from 'react';
import ReactDOM from 'react-dom/client';
import { MsalProvider } from '@azure/msal-react';
import { msalInstance, authEnabled } from './authConfig';
import './App.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));

if (authEnabled && msalInstance) {
  // Show loading while MSAL initializes (never show auth UI with stub instance)
  root.render(<div style={{textAlign:'center',marginTop:'100px'}}>Loading...</div>);

  msalInstance.initialize().then(() => {
    root.render(
      <React.StrictMode>
        <MsalProvider instance={msalInstance}>
          <App />
        </MsalProvider>
      </React.StrictMode>
    );
  }).catch((err) => {
    console.error('[MSAL] Initialization failed:', err);
    // Fall back to app without auth
    root.render(
      <React.StrictMode>
        <App />
      </React.StrictMode>
    );
  });
} else {
  root.render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
}
