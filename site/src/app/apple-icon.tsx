import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", background: "#030305" }}>
        <svg width="180" height="180" viewBox="0 0 64 64">
          <polygon points="32,12 12,50 52,50" fill="none" stroke="#fff" strokeWidth="4" strokeLinejoin="round" />
          <line x1="3" y1="21" x2="23" y2="31" stroke="#fff" strokeWidth="3" />
          <line x1="41" y1="31" x2="61" y2="19" stroke="#ff0055" strokeWidth="3" />
          <line x1="41" y1="31" x2="61" y2="31" stroke="#00ff66" strokeWidth="3" />
          <line x1="41" y1="31" x2="61" y2="43" stroke="#9900ff" strokeWidth="3" />
        </svg>
      </div>
    ),
    size,
  );
}
