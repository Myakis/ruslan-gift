const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Функции для авто-логина убраны, так как логика теперь в main процессе
  typeInDebugger: (text) => ipcRenderer.invoke('type-in-debugger', text),
  openSettings: () => ipcRenderer.send('open-settings'),
  logout: () => ipcRenderer.send('logout'),
  reloadWplan: () => ipcRenderer.send('reload-wplan'),
});
