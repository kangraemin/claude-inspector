import { useEffect, useRef, useState } from 'react';

interface ElapsedTimerProps {
  running: boolean;
}

export function ElapsedTimer({ running }: ElapsedTimerProps) {
  const [elapsed, setElapsed] = useState(0);
  const startRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    if (running) {
      startRef.current = Date.now() - elapsed * 1000;
      const tick = () => {
        const secs = Math.floor((Date.now() - (startRef.current ?? Date.now())) / 1000);
        setElapsed(secs);
        rafRef.current = requestAnimationFrame(tick);
      };
      rafRef.current = requestAnimationFrame(tick);
    } else {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      setElapsed(0);
    }
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running]);

  if (!running) return null;
  return <span style={{ fontSize: 11, color: 'var(--dim)' }}>{elapsed}s</span>;
}
