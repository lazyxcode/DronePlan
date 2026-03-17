import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const packageJson = JSON.parse(
    readFileSync(new URL('./package.json', import.meta.url), 'utf8'),
) as { version?: string }

function getBuildRevision() {
    try {
        return execSync('git rev-parse --short HEAD', {
            cwd: new URL('.', import.meta.url),
            stdio: ['ignore', 'pipe', 'ignore'],
        }).toString().trim()
    } catch {
        return 'unknown'
    }
}

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [react()],
    define: {
        __APP_VERSION__: JSON.stringify(packageJson.version ?? '0.0.0'),
        __BUILD_REV__: JSON.stringify(getBuildRevision()),
    },

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
