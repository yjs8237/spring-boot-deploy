package com.example.springbootdeploy;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Arrays;

@RestController
@Slf4j
public class HomController {

    @Autowired
    private Environment env;

    @GetMapping("/")
    public String home() {
        return Arrays.stream(env.getActiveProfiles()).findFirst().orElse("");
    }
}
