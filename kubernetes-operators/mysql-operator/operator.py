#!/usr/bin/env python3

import kopf
import kubernetes
import yaml
import logging
import os

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Инициализация Kubernetes клиента
try:
    kubernetes.config.load_incluster_config()
except:
    kubernetes.config.load_kube_config()

k8s_apps_v1 = kubernetes.client.AppsV1Api()
k8s_core_v1 = kubernetes.client.CoreV1Api()


@kopf.on.create('otus.homework', 'v1', 'mysqls')
async def create_fn(spec, name, namespace, **kwargs):
    """Обработчик создания MySQL ресурса"""

    logger.info(f"Creating MySQL instance {name} in namespace {namespace}")

    # Извлекаем параметры из spec
    image = spec.get('image')
    database = spec.get('database')
    password = spec.get('password')
    storage_size = spec.get('storage_size')

    # Создаем PersistentVolume
    pv_name = f"{name}-pv"
    pv = create_pv_manifest(pv_name, storage_size)
    try:
        k8s_core_v1.create_persistent_volume(body=pv)
        logger.info(f"Created PV {pv_name}")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 409:  # Игнорируем если уже существует
            raise

    # Создаем PersistentVolumeClaim
    pvc_name = f"{name}-pvc"
    pvc = create_pvc_manifest(pvc_name, namespace, storage_size)
    try:
        k8s_core_v1.create_namespaced_persistent_volume_claim(namespace=namespace, body=pvc)
        logger.info(f"Created PVC {pvc_name}")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 409:
            raise

    # Создаем Service
    service_name = f"{name}-service"
    service = create_service_manifest(service_name, namespace, name)
    try:
        k8s_core_v1.create_namespaced_service(namespace=namespace, body=service)
        logger.info(f"Created Service {service_name}")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 409:
            raise

    # Создаем Deployment
    deployment_name = f"{name}-deployment"
    deployment = create_deployment_manifest(
        deployment_name, namespace, name, image, database, password, pvc_name
    )
    try:
        k8s_apps_v1.create_namespaced_deployment(namespace=namespace, body=deployment)
        logger.info(f"Created Deployment {deployment_name}")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 409:
            raise

    # Обновляем статус
    return {'phase': 'Running', 'message': f'MySQL instance {name} created successfully'}


@kopf.on.delete('otus.homework', 'v1', 'mysqls')
async def delete_fn(spec, name, namespace, **kwargs):
    """Обработчик удаления MySQL ресурса"""

    logger.info(f"Deleting MySQL instance {name} from namespace {namespace}")

    # Удаляем Deployment
    try:
        k8s_apps_v1.delete_namespaced_deployment(
            name=f"{name}-deployment",
            namespace=namespace,
            body=kubernetes.client.V1DeleteOptions(propagation_policy='Foreground')
        )
        logger.info(f"Deleted Deployment {name}-deployment")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 404:
            logger.error(f"Error deleting deployment: {e}")

    # Удаляем Service
    try:
        k8s_core_v1.delete_namespaced_service(
            name=f"{name}-service",
            namespace=namespace
        )
        logger.info(f"Deleted Service {name}-service")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 404:
            logger.error(f"Error deleting service: {e}")

    # Удаляем PVC
    try:
        k8s_core_v1.delete_namespaced_persistent_volume_claim(
            name=f"{name}-pvc",
            namespace=namespace
        )
        logger.info(f"Deleted PVC {name}-pvc")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 404:
            logger.error(f"Error deleting PVC: {e}")

    # Удаляем PV
    try:
        k8s_core_v1.delete_persistent_volume(name=f"{name}-pv")
        logger.info(f"Deleted PV {name}-pv")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status != 404:
            logger.error(f"Error deleting PV: {e}")


def create_pv_manifest(name, size):
    """Создает манифест PersistentVolume"""
    return {
        'apiVersion': 'v1',
        'kind': 'PersistentVolume',
        'metadata': {
            'name': name,
            'labels': {
                'app': 'mysql',
                'managed-by': 'mysql-operator'
            }
        },
        'spec': {
            'capacity': {
                'storage': size
            },
            'accessModes': ['ReadWriteOnce'],
            'persistentVolumeReclaimPolicy': 'Delete',
            'storageClassName': 'manual',
            'hostPath': {
                'path': f'/data/{name}'
            }
        }
    }


def create_pvc_manifest(name, namespace, size):
    """Создает манифест PersistentVolumeClaim"""
    return {
        'apiVersion': 'v1',
        'kind': 'PersistentVolumeClaim',
        'metadata': {
            'name': name,
            'namespace': namespace,
            'labels': {
                'app': 'mysql',
                'managed-by': 'mysql-operator'
            }
        },
        'spec': {
            'accessModes': ['ReadWriteOnce'],
            'storageClassName': 'manual',
            'resources': {
                'requests': {
                    'storage': size
                }
            }
        }
    }


def create_service_manifest(name, namespace, mysql_name):
    """Создает манифест Service"""
    return {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {
            'name': name,
            'namespace': namespace,
            'labels': {
                'app': 'mysql',
                'mysql': mysql_name,
                'managed-by': 'mysql-operator'
            }
        },
        'spec': {
            'type': 'ClusterIP',
            'ports': [{
                'port': 3306,
                'targetPort': 3306,
                'protocol': 'TCP',
                'name': 'mysql'
            }],
            'selector': {
                'app': 'mysql',
                'mysql': mysql_name
            }
        }
    }


def create_deployment_manifest(name, namespace, mysql_name, image, database, password, pvc_name):
    """Создает манифест Deployment"""
    return {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {
            'name': name,
            'namespace': namespace,
            'labels': {
                'app': 'mysql',
                'mysql': mysql_name,
                'managed-by': 'mysql-operator'
            }
        },
        'spec': {
            'replicas': 1,
            'selector': {
                'matchLabels': {
                    'app': 'mysql',
                    'mysql': mysql_name
                }
            },
            'template': {
                'metadata': {
                    'labels': {
                        'app': 'mysql',
                        'mysql': mysql_name
                    }
                },
                'spec': {
                    'containers': [{
                        'name': 'mysql',
                        'image': image,
                        'ports': [{
                            'containerPort': 3306,
                            'name': 'mysql'
                        }],
                        'env': [
                            {
                                'name': 'MYSQL_ROOT_PASSWORD',
                                'value': password
                            },
                            {
                                'name': 'MYSQL_DATABASE',
                                'value': database
                            }
                        ],
                        'volumeMounts': [{
                            'name': 'mysql-storage',
                            'mountPath': '/var/lib/mysql'
                        }]
                    }],
                    'volumes': [{
                        'name': 'mysql-storage',
                        'persistentVolumeClaim': {
                            'claimName': pvc_name
                        }
                    }]
                }
            }
        }
    }


if __name__ == "__main__":
    # Запускаем оператор
    kopf.run()