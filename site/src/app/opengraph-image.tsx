import { ImageResponse } from "next/og";

export const alt = "PRISMA — сообщество Minecraft";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", background: "#030305", position: "relative", color: "#fff" }}>
        <svg width="1200" height="630" viewBox="0 0 1200 630" style={{ position: "absolute", inset: 0 }}>
          <line x1="0" y1="250" x2="470" y2="330" stroke="#fff" strokeWidth="6" strokeLinecap="round" />
          <line x1="690" y1="330" x2="1200" y2="140" stroke="#ff0055" strokeWidth="6" />
          <line x1="690" y1="330" x2="1200" y2="260" stroke="#ffaa00" strokeWidth="6" />
          <line x1="690" y1="330" x2="1200" y2="380" stroke="#00ff66" strokeWidth="6" />
          <line x1="690" y1="330" x2="1200" y2="500" stroke="#9900ff" strokeWidth="6" />
          <polygon points="580,190 460,430 700,430" fill="#0b0b10" stroke="#fff" strokeWidth="8" strokeLinejoin="round" />
        </svg>
        <div style={{ position: "absolute", left: 70, bottom: 60, display: "flex", flexDirection: "column" }}>
          <div style={{ fontSize: 84, fontWeight: 800, letterSpacing: -2 }}>PRISMA</div>
          <div style={{ fontSize: 30, color: "#a1a1aa" }}>Сообщество Minecraft-сервера</div>
        </div>
      </div>
    ),
    size,
  );
}
