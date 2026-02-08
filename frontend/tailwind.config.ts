import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{js,ts,jsx,tsx}", "./components/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#0f172a",
        ember: "#f97316",
        mint: "#10b981",
        steel: "#334155",
      },
      boxShadow: {
        glow: "0 20px 60px rgba(249, 115, 22, 0.25)",
      },
    },
  },
  plugins: [],
};

export default config;
