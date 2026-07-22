// Global Back (10009) priority chain. Screens/overlays register interceptors;
// the most recently registered one gets the key first (LIFO). When nobody
// consumes it, App pops the navigation stack or arms app exit at the root.

type BackInterceptor = () => boolean;

const interceptors: BackInterceptor[] = [];

export function registerBackInterceptor(fn: BackInterceptor): () => void {
  interceptors.push(fn);
  return () => {
    const index = interceptors.indexOf(fn);
    if (index >= 0) interceptors.splice(index, 1);
  };
}

/** Returns true when an interceptor consumed the key. */
export function dispatchBack(): boolean {
  for (let i = interceptors.length - 1; i >= 0; i--) {
    if (interceptors[i]()) return true;
  }
  return false;
}
