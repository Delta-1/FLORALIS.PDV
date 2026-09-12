const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('FLORALIS_NATIVE_APP', Object.freeze({
  platform: 'desktop',
  container: 'electron'
}));
