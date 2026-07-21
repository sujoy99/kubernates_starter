package com.example.helloservice.service;

/**
 * The JSON shape returned by GET /api/hello.
 * A Java record is a compact, immutable data carrier - no boilerplate getters/constructors needed.
 */
public record GreetingResponse(String service, String message) {
}
