'use client';

import { type SVGProps } from 'react';

export type LogoProps = SVGProps<SVGSVGElement>;

export function Logo({
  className = '',
  ...props
}: LogoProps) {
  return (
    <svg
      {...props}
      viewBox="0 0 32 32"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      className={className}
    >
      <rect
        width="32"
        height="32"
        x="0"
        y="0"
        rx="8"
        className="fill-slate-900 dark:fill-blue-600"
      />
      <path
        d="M20.9615 9.72528L24.9615 23.7253L23.0385 24.2747L19.0385 10.2747L20.9615 9.72528ZM19.0632 10.2885L19.0385 10.2747C18.8846 9.73627 19.1868 9.19232 19.7253 9.03848C20.2637 8.88463 20.8077 9.18683 20.9615 9.72528L20.9478 9.75L19.0632 10.2885ZM24.9368 23.7115L24.9615 23.7253C25.1154 24.2637 24.8132 24.8077 24.2747 24.9615C23.7363 25.1154 23.1923 24.8132 23.0385 24.2747L23.0522 24.25L24.9368 23.7115Z"
        className="fill-white dark:fill-slate-900"
        fillRule="nonzero"
      />
      <path
        d="M17 10L17 24L15 24L15 10L17 10ZM15.02 10.02L15 10C15 9.44 15.44 9 16 9C16.56 9 17 9.44 17 10L16.98 10.02L15.02 10.02ZM16.98 23.98L17 24C17 24.56 16.56 25 16 25C15.44 25 15 24.56 15 24L15.02 23.98L16.98 23.98Z"
        className="fill-white dark:fill-slate-900"
        fillRule="nonzero"
      />
      <path
        d="M13 12L13 24L11 24L11 12L13 12ZM11.02 12.02L11 12C11 11.44 11.44 11 12 11C12.56 11 13 11.44 13 12L12.98 12.02L11.02 12.02ZM12.98 23.98L13 24C13 24.56 12.56 25 12 25C11.44 25 11 24.56 11 24L11.02 23.98L12.98 23.98Z"
        className="fill-white dark:fill-slate-900"
        fillRule="nonzero"
      />
      <path
        d="M9 8L9 24L7 24L7 8L9 8ZM7.02 8.02L7 8C7 7.44 7.44 7 8 7C8.56 7 9 7.44 9 8L8.98 8.02L7.02 8.02ZM8.98 23.98L9 24C9 24.56 8.56 25 8 25C7.44 25 7 24.56 7 24L7.02 23.98L8.98 23.98Z"
        className="fill-white dark:fill-slate-900"
        fillRule="nonzero"
      />
    </svg>
  );
}
