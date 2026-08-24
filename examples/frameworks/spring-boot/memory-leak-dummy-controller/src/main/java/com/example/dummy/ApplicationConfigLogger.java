package com.example.dummy;

import java.util.Locale;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationEnvironmentPreparedEvent;
import org.springframework.boot.context.logging.LoggingApplicationListener;
import org.springframework.context.ApplicationListener;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.EnumerablePropertySource;
import org.springframework.core.env.PropertySource;

public class ApplicationConfigLogger
        implements ApplicationListener<ApplicationEnvironmentPreparedEvent>, Ordered {

    private static final Logger log = LoggerFactory.getLogger(ApplicationConfigLogger.class);

    private static final String MASKED_VALUE = "******";
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

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

    @Override
    public int getOrder() {
        return LoggingApplicationListener.DEFAULT_ORDER + 1;
    }

    @Override
    public void onApplicationEvent(ApplicationEnvironmentPreparedEvent event) {
        if (!log.isDebugEnabled()) {
            return;
        }

        ConfigurableEnvironment environment = event.getEnvironment();
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
                    : getPropertyValue(environment, propertyName);

            config.put(propertyName, value);
        }

        try {
            String json = OBJECT_MAPPER
                    .writerWithDefaultPrettyPrinter()
                    .writeValueAsString(config);

            log.debug("Application configuration prepared before context startup:\n{}", json);
        } catch (JsonProcessingException ex) {
            log.warn("Failed to serialize application configuration for debug logging", ex);
        }
    }

    private static boolean isSensitive(String name) {
        String lower = name.toLowerCase(Locale.ROOT);

        return SENSITIVE_WORDS.stream()
                .anyMatch(lower::contains);
    }

    private static Object getPropertyValue(ConfigurableEnvironment environment, String propertyName) {
        try {
            return environment.getProperty(propertyName);
        } catch (RuntimeException ex) {
            return "<failed to resolve: " + ex.getClass().getSimpleName() + ": " + ex.getMessage() + ">";
        }
    }
}
