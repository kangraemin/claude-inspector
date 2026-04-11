interface SpinnerProps {
  size?: number;
  color?: string;
}

export function Spinner({ size = 13, color = 'var(--blue)' }: SpinnerProps) {
  return (
    <span
      style={{
        display: 'inline-block',
        width: size,
        height: size,
        border: `2px solid var(--border)`,
        borderTopColor: color,
        borderRadius: '50%',
        animation: 'spin .7s linear infinite',
        flexShrink: 0,
      }}
    />
  );
}
