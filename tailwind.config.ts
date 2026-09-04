import type { Config } from 'tailwindcss'

const config: Config = {
  darkMode: ['class'],
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}', './lib/**/*.{ts,tsx}'],
  theme: { extend: { borderRadius: { '2xl': '1rem' }, boxShadow: { premium: '0 20px 60px rgba(2, 8, 23, .12)' } } },
  plugins: [],
}
export default config
