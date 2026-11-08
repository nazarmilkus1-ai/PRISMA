import path from "node:path";
import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs/config";

const localLucide = path.resolve(process.cwd(), "node_modules/lucide-react");

const nextConfig: NextConfig = {
  basePath: "/admin",
  reactStrictMode: true,
  poweredByHeader: false,
  transpilePackages: ["@prisma-eco/ui", "@prisma-eco/contracts"],
  webpack(config) {
    config.resolve ??= {};
    config.resolve.alias = {
      ...(config.resolve.alias ?? {}),
      "lucide-react": localLucide,
    };
    return config;
  },
};

export default withSentryConfig(nextConfig, {
  silent: true,
});
