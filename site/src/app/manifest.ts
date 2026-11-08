import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "PRISMA",
    short_name: "PRISMA",
    description: "Сообщество Minecraft-сервера PRISMA",
    start_url: "/",
    display: "standalone",
    background_color: "#030305",
    theme_color: "#030305",
    icons: [{ src: "/favicon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" }],
  };
}
