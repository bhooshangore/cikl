class role::does_everything {
  include profile::base
  include profile::logstash
  include profile::elasticsearch
  include profile::rabbitmq
  include profile::worker
  include profile::smrt
  include profile::mongodb
}
