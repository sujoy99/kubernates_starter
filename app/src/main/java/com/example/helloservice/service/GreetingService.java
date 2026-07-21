package com.example.helloservice.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class GreetingService {

    private final String appName;
    private final String greetingMessage;

    public GreetingService(
            @Value("${app.name}") String appName,
            @Value("${app.greeting.message}") String greetingMessage) {
        this.appName = appName;
        this.greetingMessage = greetingMessage;
    }

    public GreetingResponse getGreeting() {
        return new GreetingResponse(appName, greetingMessage);
    }
}
