package com.example.dummy;

import java.util.Locale;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.EnumerablePropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.stereotype.Component;

@Component
public class ApplicationConfigLogger implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(ApplicationConfigLogger.class);

    private static final String MASKED_VALUE = "******";

    private static final Set<String> SENSITIVE_WORDS = Set.of(
            "api-key",
            "apikey",
            "authorization",
            "bearer",
            "cert",
            "cookie",
            "credential",
            "key",
            "oauth",
            "passphrase",
            "passwd",
            "password",
            "private",
            "private-key",
            "secret",
            "session",
            "token");

    private final ConfigurableEnvironment environment;
    private final ObjectMapper objectMapper;

    public ApplicationConfigLogger(
            ConfigurableEnvironment environment,
            ObjectMapper objectMapper) {
        this.environment = environment;
        this.objectMapper = objectMapper;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (!log.isDebugEnabled()) {
            return;
        }

        Set<String> propertyNames = new TreeSet<>();

        for (PropertySource<?> propertySource : environment.getPropertySources()) {
            if (propertySource instanceof EnumerablePropertySource<?> enumerable) {
                for (String propertyName : enumerable.getPropertyNames()) {
                    propertyNames.add(propertyName);
                }
            }
        }

        TreeMap<String, Object> config = new TreeMap<>();

        for (String propertyName : propertyNames) {
            Object value = isSensitive(propertyName)
                    ? MASKED_VALUE
                    : environment.getProperty(propertyName);

            config.put(propertyName, value);
        }

        try {
            String json = objectMapper
                    .writerWithDefaultPrettyPrinter()
                    .writeValueAsString(config);

            log.debug("Application configuration:\n{}", json);
        } catch (JsonProcessingException ex) {
            log.warn("Failed to serialize application configuration for debug logging", ex);
        }
    }

    private static boolean isSensitive(String name) {
        String lower = name.toLowerCase(Locale.ROOT);

        return SENSITIVE_WORDS.stream()
                .anyMatch(lower::contains);
    }
}
