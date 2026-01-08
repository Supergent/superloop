import { createRoot } from "react-dom/client";

import { App } from "./App.js";
import { styles } from "./styles.js";

const styleTag = document.createElement("style");
styleTag.textContent = styles;
document.head.appendChild(styleTag);

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Root element not found");
}

createRoot(rootElement).render(<App />);
