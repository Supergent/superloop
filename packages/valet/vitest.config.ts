import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@tauri-apps/api/core': path.resolve(__dirname, 'src/test/tauri-mock.ts'),
      '@tauri-apps/api/tauri': path.resolve(__dirname, 'src/test/tauri-mock.ts'),
      '@tauri-apps/api/event': path.resolve(__dirname, 'src/test/event-mock.ts'),
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    include: ['src/**/__tests__/**/*.{test,spec}.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'src/test/',
        '**/*.d.ts',
        '**/*.config.*',
        '**/mockData',
      ],
    },
  },
});
