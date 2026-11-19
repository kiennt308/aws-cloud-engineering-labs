// OrderFlow Global - CloudFront Function (viewer-response, ES5.1)
// Copyright 2026 Kien Nguyen (Apache-2.0 License)
// Executes in <1 ms at edge locations without origin round-trips.

function handler(event) {
  var response = event.response;
  var headers = response.headers;

  headers['strict-transport-security'] = {
    value: 'max-age=63072000; includeSubDomains; preload'
  };
  headers['content-security-policy'] = {
    value: "default-src 'self'; frame-ancestors 'none'; object-src 'none'"
  };
  headers['x-content-type-options'] = {
    value: 'nosniff'
  };
  headers['referrer-policy'] = {
    value: 'strict-origin-when-cross-origin'
  };
  headers['x-frame-options'] = {
    value: 'DENY'
  };
  headers['permissions-policy'] = {
    value: 'geolocation=(), microphone=(), camera=()'
  };

  delete headers['server'];
  delete headers['x-powered-by'];

  return response;
}
