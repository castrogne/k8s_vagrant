FROM maven:3.8.6-openjdk-11 as DEPS

WORKDIR /usr/src/app
COPY ./pom.xml ./
RUN mvn dependency:resolve

FROM maven:3.8.6-openjdk-11 as BUILDER

COPY --from=DEPS /root/.m2  /root/.m2

WORKDIR /usr/src/app
COPY --from=DEPS /usr/src/app/pom.xml  ./pom.xml
COPY ./src ./src

RUN mvn clean package

FROM openjdk:23-ea-11-jdk-slim

WORKDIR /usr/app
COPY --from=BUILDER /usr/src/app/target/*.jar ./autoscale.jar
ENTRYPOINT java -jar autoscale.jar