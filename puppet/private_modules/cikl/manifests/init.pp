class cikl (
  $elasticsearch_cluster_name = $cikl::params::elasticsearch_cluster_name,
  $elasticsearch_template = $cikl::params::elasticsearch_template,
  $rabbitmq_host     = $cikl::params::rabbitmq_host,
  $rabbitmq_port     = $cikl::params::rabbitmq_port,
  $rabbitmq_username = $cikl::params::rabbitmq_username, 
  $rabbitmq_password = $cikl::params::rabbitmq_password,
  $rabbitmq_vhost    = $cikl::params::rabbitmq_vhost,
  $use_perlbrew      = $cikl::params::use_perlbrew
) inherits cikl::params {
  include cikl::elasticsearch::install
  include cikl::rabbitmq::install
  include cikl::logstash::install
  include cikl::smrt::install
  
}
