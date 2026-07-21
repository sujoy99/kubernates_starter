package com.example.helloservice.service;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class GreetingServiceTest {

    @Test
    void getGreeting_returnsConfiguredAppNameAndMessage() {
        GreetingService service = new GreetingService("test-service", "Hi there");

        GreetingResponse response = service.getGreeting();

        assertThat(response.service()).isEqualTo("test-service");
        assertThat(response.message()).isEqualTo("Hi there");
    }
}
