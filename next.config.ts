import type { NextConfig } from "next";
const nextConfig: NextConfig = {
  reactStrictMode: true,
  agentRules: false,
  outputFileTracingIncludes: {
    "/kpi/transportadministration/transportdokument/pdf": ["./src/lib/hub/transport-document/transport-document-template.pdf"],
  },
  serverExternalPackages: ["pdf-parse", "@napi-rs/canvas"],
};
export default nextConfig;
