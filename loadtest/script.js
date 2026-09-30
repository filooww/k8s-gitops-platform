import http from "k6/http";
import { check, sleep } from "k6";
import { Trend } from "k6/metrics";

const BASE = __ENV.BASE_URL || "http://myapp.localhost:8080";
const HOST_HEADER = __ENV.HOST_HEADER || "";
const params = HOST_HEADER ? { headers: { Host: HOST_HEADER } } : {};
const workLatency = new Trend("work_latency_ms");

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 20 }, 
        { duration: "60s", target: 60 }, 
        { duration: "30s", target: 0 }, 
      ],
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],   
    http_req_duration: ["p(95)<2000"], 
  },
};

export default function () {
  const res = http.get(`${BASE}/work?iterations=300000`, params);
  workLatency.add(res.timings.duration);
  check(res, { "status is 200": (r) => r.status === 200 });
  sleep(0.2);
}
