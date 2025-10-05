import { defineConfig, globalIgnores } from 'eslint/config'
import eslintPluginUnicorn from 'eslint-plugin-unicorn'
import eslint from '@eslint/js'
import tseslint from 'typescript-eslint'
import globals from 'globals'

console.log(eslintPluginUnicorn.configs.recommended)
export default defineConfig([
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  eslintPluginUnicorn.configs.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.browser,
      },
    },
  },
  {
    rules: {
      'unicorn/better-regex': 'warn',
    },
  },
  globalIgnores(['./vendor']),
])
