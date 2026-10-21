// One JSON object per line on stdout/stderr, which hosts such as Render keep
// and let you search.

export type LogFields = Record<string, unknown>;
export type Logger = (level: "info" | "warn" | "error", msg: string, fields?: LogFields) => void;

export const jsonLogger: Logger = (level, msg, fields = {}) => {
  const line = JSON.stringify({ time: new Date().toISOString(), level, msg, ...fields });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
};
