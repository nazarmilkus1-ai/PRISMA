/** The PRISMA mark: a prism outline. Inherits colour from the surrounding text. */
export function PrismMark({ size = 18 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <polygon points="12 3 2 21 22 21" />
    </svg>
  );
}
