/**
 * Xtream Codes API client, ported from
 * apps/ios/another-iptv-player/Networking/XtreamAPIClient.swift.
 */

import {
  DEFAULT_TIMEOUT_MS,
  XtreamApiError,
  fetchWithRetry,
  normalizeXtreamBaseURL,
} from "./http";
import type {
  XtreamAuthResponse,
  XtreamCategory,
  XtreamLiveStream,
  XtreamSeriesInfo,
  XtreamSeriesListItem,
  XtreamVodInfo,
  XtreamVodStream,
} from "../models/xtream";
import {
  XtreamDecodeError,
  parseXtreamAuthResponse,
  parseXtreamCategoryList,
  parseXtreamLiveStreamList,
  parseXtreamSeriesInfo,
  parseXtreamSeriesList,
  parseXtreamVodInfo,
  parseXtreamVodStreamList,
} from "../models/xtream";

export interface XtreamCredentials {
  serverURL: string;
  username: string;
  password: string;
}

export type XtreamCategoryKind = "live" | "vod" | "series";

const CATEGORY_ACTIONS: { [K in XtreamCategoryKind]: string } = {
  live: "get_live_categories",
  vod: "get_vod_categories",
  series: "get_series_categories",
};

interface QueryParam {
  name: string;
  value: string;
}

export class XtreamClient {
  private readonly credentials: XtreamCredentials;
  private readonly timeoutMs: number;

  constructor(
    credentials: XtreamCredentials,
    timeoutMs: number = DEFAULT_TIMEOUT_MS,
  ) {
    this.credentials = credentials;
    this.timeoutMs = timeoutMs;
  }

  // MARK: - API methods

  /**
   * Hits the bare player_api.php endpoint (no `action` param). Throws an
   * "unauthenticated" XtreamApiError when `user_info` is missing or its
   * `auth` flag is 0. A missing `auth` field passes, matching the iOS client —
   * some quirky panels omit it while returning a valid user_info.
   */
  async verify(): Promise<XtreamAuthResponse> {
    const raw = await this.fetchJSON([]);
    const response = parseXtreamAuthResponse(raw);
    if (!response.userInfo || response.userInfo.auth === 0) {
      throw new XtreamApiError(
        "unauthenticated",
        "Xtream authentication failed (invalid credentials or expired account)",
      );
    }
    return response;
  }

  async getCategories(kind: XtreamCategoryKind): Promise<XtreamCategory[]> {
    const raw = await this.fetchJSON([
      { name: "action", value: CATEGORY_ACTIONS[kind] },
    ]);
    return this.decode(() => parseXtreamCategoryList(raw));
  }

  async getLiveStreams(categoryId?: string): Promise<XtreamLiveStream[]> {
    const raw = await this.fetchJSON(
      withCategory([{ name: "action", value: "get_live_streams" }], categoryId),
    );
    return this.decode(() => parseXtreamLiveStreamList(raw));
  }

  async getVodStreams(categoryId?: string): Promise<XtreamVodStream[]> {
    const raw = await this.fetchJSON(
      withCategory([{ name: "action", value: "get_vod_streams" }], categoryId),
    );
    return this.decode(() => parseXtreamVodStreamList(raw));
  }

  async getSeries(categoryId?: string): Promise<XtreamSeriesListItem[]> {
    const raw = await this.fetchJSON(
      withCategory([{ name: "action", value: "get_series" }], categoryId),
    );
    return this.decode(() => parseXtreamSeriesList(raw));
  }

  async getSeriesInfo(seriesId: number): Promise<XtreamSeriesInfo> {
    const raw = await this.fetchJSON([
      { name: "action", value: "get_series_info" },
      { name: "series_id", value: String(seriesId) },
    ]);
    return this.decode(() => parseXtreamSeriesInfo(raw));
  }

  async getVodInfo(vodId: number): Promise<XtreamVodInfo> {
    const raw = await this.fetchJSON([
      { name: "action", value: "get_vod_info" },
      { name: "vod_id", value: String(vodId) },
    ]);
    return this.decode(() => parseXtreamVodInfo(raw));
  }

  // MARK: - Internals

  buildURL(params: QueryParam[]): string {
    const base = normalizeXtreamBaseURL(this.credentials.serverURL);
    // Built by hand: URLSearchParams support on Chromium 56 is spotty.
    const query: QueryParam[] = [
      { name: "username", value: this.credentials.username.trim() },
      { name: "password", value: this.credentials.password.trim() },
      ...params,
    ];
    const encoded = query
      .map(
        (param) =>
          `${encodeURIComponent(param.name)}=${encodeURIComponent(param.value)}`,
      )
      .join("&");
    return `${base}?${encoded}`;
  }

  private async fetchJSON(params: QueryParam[]): Promise<unknown> {
    const url = this.buildURL(params);
    const response = await fetchWithRetry(url, this.timeoutMs);

    if (response.status < 200 || response.status > 299) {
      throw new XtreamApiError(
        "server",
        `HTTP ${response.status}`,
        response.status,
      );
    }

    let body: string;
    try {
      body = await response.text();
    } catch (error) {
      throw new XtreamApiError(
        "network",
        `Failed to read response body: ${messageOf(error)}`,
      );
    }

    try {
      return JSON.parse(body) as unknown;
    } catch (error) {
      throw new XtreamApiError(
        "decoding",
        `Response is not valid JSON: ${messageOf(error)}`,
      );
    }
  }

  /** Wraps model-level decode failures into a typed "decoding" error. */
  private decode<T>(parse: () => T): T {
    try {
      return parse();
    } catch (error) {
      if (error instanceof XtreamDecodeError) {
        throw new XtreamApiError("decoding", error.message);
      }
      throw error;
    }
  }
}

function withCategory(
  params: QueryParam[],
  categoryId: string | undefined,
): QueryParam[] {
  if (categoryId !== undefined) {
    return [...params, { name: "category_id", value: categoryId }];
  }
  return params;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
