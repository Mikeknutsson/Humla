import type { NextConfig } from "next";
const nextConfig: NextConfig = {
  reactStrictMode: true,
  agentRules: false,
  serverExternalPackages: ["pdf-parse", "@napi-rs/canvas"],
};
export default nextConfig;
