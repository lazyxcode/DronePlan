import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [react()],

    // Prevent vite from obscuring rust errors
    clearScreen: false,

    // Tauri expects a fixed port, fail if that port is not available
    server: {
        port: 1420,
        strictPort: true,
        watch: {
            // Tell vite to ignore watching `src-tauri`
            ignored: ["**/src-tauri/**"],
        },
    },

    // To make use of `TAURI_DEBUG` and other env variables
    // See https://tauri.app/v1/api/config/#buildconfig.beforedevcommand
    envPrefix: ['VITE_', 'TAURI_'],
})
