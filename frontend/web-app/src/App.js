import React, { useState, useContext } from 'react';
import { MsalContext } from '@azure/msal-react';
import { InteractionStatus } from '@azure/msal-browser';
import { authEnabled } from './authConfig';
import ProductList from './components/ProductList';
import StatusPanel from './components/StatusPanel';
import StatusToggleButton from './components/StatusToggleButton';
import SignInButton from './components/SignInButton';
import './App.css';

function AppContent() {
  return (
    <main>
      <ProductList />
    </main>
  );
}

// Handles all MSAL states: loading, unauthenticated, authenticated
function AuthGate() {
  const msalContext = useContext(MsalContext);

  // MsalProvider not mounted yet (initial render before MSAL init)
  if (!msalContext || !msalContext.instance) {
    return (
      <div className="auth-prompt">
        <p>Initializing authentication...</p>
      </div>
    );
  }

  const { inProgress, accounts } = msalContext;
  const isAuthenticated = accounts && accounts.length > 0;

  if (inProgress !== InteractionStatus.None) {
    return (
      <div className="auth-prompt">
        <p>Loading...</p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <div className="auth-prompt">
        <h2>Sign in to continue</h2>
        <p>This application requires authentication. Click "Sign In" above to log in with your Azure AD account.</p>
      </div>
    );
  }

  return <AppContent />;
}

// Only render SignInButton when MsalProvider is available
function AuthHeader() {
  const msalContext = useContext(MsalContext);
  if (!msalContext || !msalContext.instance) return null;
  return (
    <div className="header-auth">
      <SignInButton />
    </div>
  );
}

function App() {
  const [panelOpen, setPanelOpen] = useState(false);

  return (
    <div className={`App ${panelOpen ? 'panel-open' : ''}`}>
      <header className="App-header">
        <div className="header-content">
          <div>
            <h1>Dapr Microservices Demo</h1>
            <p>Product Catalog & Order Management</p>
          </div>
          {authEnabled && <AuthHeader />}
        </div>
      </header>

      {authEnabled ? <AuthGate /> : <AppContent />}

      <footer>
        <p>Powered by Dapr on Kubernetes</p>
      </footer>
      <StatusPanel open={panelOpen} onClose={() => setPanelOpen(false)} />
      <StatusToggleButton open={panelOpen} onClick={() => setPanelOpen(p => !p)} />
    </div>
  );
}

export default App;
