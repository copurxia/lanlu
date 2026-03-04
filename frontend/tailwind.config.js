/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: ["class"],
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    container: {
      center: true,
      padding: "2rem",
      screens: {
        "2xl": "1400px",
      },
    },
    extend: {
      screens: {
        '3xl': '1920px',
        '4xl': '2560px',
        '5xl': '3200px',
      },
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
        },
        popover: {
          DEFAULT: "hsl(var(--popover))",
          foreground: "hsl(var(--popover-foreground))",
        },
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
      spacing: {
        // Modal尺寸 - 基于CSS变量
        'modal-xs': '20rem',
        'modal-sm': 'var(--modal-size-sm)',
        'modal-md': 'var(--modal-size-md)',
        'modal-lg': 'var(--modal-size-lg)',
        'modal-xl': 'var(--modal-size-xl)',
      },
      zIndex: {
        // Modal层级管理
        'modal-overlay': 'var(--z-modal-overlay)',
        'modal-content': 'var(--z-modal-content)',
        'toast': 'var(--z-toast)',
        'tooltip': 'var(--z-tooltip)',
      },
      keyframes: {
        "accordion-down": {
          from: { height: "0" },
          to: { height: "var(--radix-accordion-content-height)" },
        },
        "accordion-up": {
          from: { height: "var(--radix-accordion-content-height)" },
        },
        "fade-in": {
          "0%": { opacity: "0" },
          "100%": { opacity: "1" },
        },
        "slide-in-from-bottom": {
          "0%": { transform: "translateY(1rem)", opacity: "0" },
          "100%": { transform: "translateY(0)", opacity: "1" },
        },
        "shake": {
          "0%, 100%": { transform: "translateX(0)" },
          "25%": { transform: "translateX(-5px)" },
          "75%": { transform: "translateX(5px)" },
        },
        "archive-card-in": {
          "0%": { transform: "translate3d(0, 14px, 0) scale(0.96) rotate(-0.25deg)", opacity: "0" },
          "55%": { transform: "translate3d(0, -2px, 0) scale(1.02) rotate(0.15deg)", opacity: "1" },
          "80%": { transform: "translate3d(0, 1px, 0) scale(0.995) rotate(-0.05deg)" },
          "100%": { transform: "translate3d(0, 0, 0) scale(1) rotate(0deg)", opacity: "1" },
        },
        "sheet-overlay-in": {
          "0%": { opacity: "0" },
          "100%": { opacity: "1" },
        },
        "sheet-overlay-out": {
          "0%": { opacity: "1" },
          "100%": { opacity: "0" },
        },
        "sheet-left-in": {
          "0%": { transform: "translate3d(-100%, 0, 0)", opacity: "0" },
          "100%": { transform: "translate3d(0, 0, 0)", opacity: "1" },
        },
        "sheet-left-out": {
          "0%": { transform: "translate3d(0, 0, 0)", opacity: "1" },
          "100%": { transform: "translate3d(-100%, 0, 0)", opacity: "0" },
        },
        "sheet-right-in": {
          "0%": { transform: "translate3d(18px, 0, 0) scale(0.985)", opacity: "0" },
          "100%": { transform: "translate3d(0, 0, 0) scale(1)", opacity: "1" },
        },
        "sheet-right-out": {
          "0%": { transform: "translate3d(0, 0, 0) scale(1)", opacity: "1" },
          "100%": { transform: "translate3d(18px, 0, 0) scale(0.985)", opacity: "0" },
        },
        "sheet-top-in": {
          "0%": { transform: "translate3d(0, -14px, 0) scale(0.99)", opacity: "0" },
          "100%": { transform: "translate3d(0, 0, 0) scale(1)", opacity: "1" },
        },
        "sheet-top-out": {
          "0%": { transform: "translate3d(0, 0, 0) scale(1)", opacity: "1" },
          "100%": { transform: "translate3d(0, -14px, 0) scale(0.99)", opacity: "0" },
        },
        "sheet-bottom-in": {
          "0%": { transform: "translate3d(0, 14px, 0) scale(0.99)", opacity: "0" },
          "100%": { transform: "translate3d(0, 0, 0) scale(1)", opacity: "1" },
        },
        "sheet-bottom-out": {
          "0%": { transform: "translate3d(0, 0, 0) scale(1)", opacity: "1" },
          "100%": { transform: "translate3d(0, 14px, 0) scale(0.99)", opacity: "0" },
        },
      },
      animation: {
        "accordion-down": "accordion-down 0.2s ease-out",
        "accordion-up": "accordion-up 0.2s ease-out",
        "fade-in": "fade-in 0.5s ease-out",
        "slide-in-from-bottom": "slide-in-from-bottom 0.5s ease-out",
        "shake": "shake 0.3s ease-in-out",
        "archive-card-in": "archive-card-in 520ms cubic-bezier(0.16, 1, 0.3, 1) both",
        "sheet-overlay-in": "sheet-overlay-in 220ms ease-out both",
        "sheet-overlay-out": "sheet-overlay-out 180ms ease-in both",
        "sheet-left-in": "sheet-left-in 320ms cubic-bezier(0.16, 1, 0.3, 1) both",
        "sheet-left-out": "sheet-left-out 160ms cubic-bezier(0.4, 0, 1, 1) both",
        "sheet-right-in": "sheet-right-in 360ms cubic-bezier(0.16, 1, 0.3, 1) both",
        "sheet-right-out": "sheet-right-out 220ms cubic-bezier(0.4, 0, 1, 1) both",
        "sheet-top-in": "sheet-top-in 320ms cubic-bezier(0.16, 1, 0.3, 1) both",
        "sheet-top-out": "sheet-top-out 200ms cubic-bezier(0.4, 0, 1, 1) both",
        "sheet-bottom-in": "sheet-bottom-in 320ms cubic-bezier(0.16, 1, 0.3, 1) both",
        "sheet-bottom-out": "sheet-bottom-out 200ms cubic-bezier(0.4, 0, 1, 1) both",
      },
    },
  },
  plugins: [],
}
