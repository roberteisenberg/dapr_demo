import React from 'react';
import ProductList from './components/ProductList';
import './App.css';

function App() {
  return (
    <div className="App">
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
    </div>
  );
}

export default App;
