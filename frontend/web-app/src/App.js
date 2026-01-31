import React, { useState } from 'react';
import ProductList from './components/ProductList';
import StatusPanel from './components/StatusPanel';
import StatusToggleButton from './components/StatusToggleButton';
import './App.css';

function App() {
  const [panelOpen, setPanelOpen] = useState(false);

  return (
    <div className={`App ${panelOpen ? 'panel-open' : ''}`}>
      <header className="App-header">
        <h1>Dapr Microservices Demo</h1>
        <p>Product Catalog & Order Management</p>
      </header>
      <main>
        <ProductList />
      </main>
      <footer>
        <p>Powered by Dapr on Kubernetes</p>
      </footer>
      <StatusPanel open={panelOpen} onClose={() => setPanelOpen(false)} />
      <StatusToggleButton open={panelOpen} onClick={() => setPanelOpen(p => !p)} />
    </div>
  );
}

export default App;
