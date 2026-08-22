import js from '@eslint/js'
import prettier from 'eslint-config-prettier'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  {
    ignores: ['out/**', 'release/**', 'build/**', 'node_modules/**', '*.d.ts']
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  // 主进程 / 预加载 / 共享层 / 构建脚本：Node 环境
  {
    files: [
      'src/main/**/*.ts',
      'src/preload/**/*.ts',
      'src/shared/**/*.ts',
      'tests/**/*.ts',
      'scripts/**/*.js',
      '*.config.ts',
      '*.config.mjs'
    ],
    languageOptions: {
      globals: { ...globals.node }
    }
  },

  // 渲染进程：浏览器环境 + React 规则
  {
    files: ['src/renderer/**/*.{ts,tsx}'],
    languageOptions: {
      globals: { ...globals.browser },
      parserOptions: { ecmaFeatures: { jsx: true } }
    },
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': ['warn', { allowConstantExport: true }]
    }
  },

  {
    rules: {
      // 下划线开头表示「刻意不用」，IPC 处理器的 _e 到处都是
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrors: 'none' }
      ],
      // 与渲染进程之间的 IPC 负载天然是 unknown/any，收窄由各处的运行时校验负责
      '@typescript-eslint/no-explicit-any': 'off',
      // `条件 ? a() : b()` 是本项目里翻页/方向判断的固定写法，短路副作用仍然禁止
      '@typescript-eslint/no-unused-expressions': [
        'error',
        { allowTernary: true, allowShortCircuit: false }
      ],
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' }
      ],
      eqeqeq: ['error', 'smart'],
      'no-console': ['warn', { allow: ['warn', 'error', 'log'] }]
    }
  },

  // 测试里用 any 构造脏数据是常态
  {
    files: ['tests/**/*.ts'],
    rules: {
      '@typescript-eslint/no-unused-expressions': 'off'
    }
  },

  // 图标生成脚本是独立跑的 CJS 脚本
  {
    files: ['scripts/**/*.js'],
    rules: {
      '@typescript-eslint/no-require-imports': 'off'
    }
  },

  prettier
)
