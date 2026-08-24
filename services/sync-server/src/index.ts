import { createApp } from "./app";
import { config } from "./config";

const app = createApp();
app.listen(config.port, () => {
  console.log(`sync-server listening on :${config.port}`);
});
