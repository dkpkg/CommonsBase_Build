# From https://gitlab.kitware.com/cmake/cmake/-/tree/bad6831d5a504168cec407cf3f8bea7bdf14d679/Help/guide/tutorial/Step0
cmake_minimum_required(VERSION 3.23)

project(Tutorial)

add_executable(hello)
target_sources(hello
  PRIVATE
    HelloWorld.cxx
)
