# Layihənin izahı (müsahibəyə hazırlıq)

## Bir cümlə ilə

Kubernetes-də 3 qatlı tətbiqi bir neçə müdafiə qatı ilə qoruyuram və hər qatın həqiqətən işlədiyini CI-da real klasterdə hücum simulyasiyası ilə yoxlayıram.

## Qatlar və sadə izah

**1. Pod Security Standard (restricted)**
Namespace-ə etiket qoyuruq və Kubernetes API server-in özü təhlükəli pod-ları qəbul etmir: root kimi işləyən, privileged olan, host fayl sisteminə qoşulan. Test bunu `--dry-run=server` ilə yoxlayır, yəni sorğu admission-dan keçir, amma heç nə yaranmır.

**2. Konteyner hardening**
Hər konteyner root olmayan istifadəçi ilə işləyir, fayl sistemi yalnız oxumaq üçündür, Linux capability-lərinin hamısı çıxarılıb, seccomp aktivdir. Service account token pod-a qoşulmur, çünki tətbiq Kubernetes API-yə müraciət etmir. Pod ələ keçirilsə belə, hücumçunun əlində klaster açarı olmur.

**3. RBAC**
Developer baxa bilir, amma secret oxuya, pod-a girə (exec) bilmir. CI yeni versiya yerləşdirə bilir, amma secret oxuya bilmir. Test `kubectl auth can-i --as=...` ilə hər rolu "geyinib" yoxlayır.

**4. NetworkPolicy (zero trust)**
Əvvəlcə hər şey bağlanır (default deny), sonra yalnız lazım olan yollar açılır: frontend → api → redis. İnternetə çıxış yoxdur. Kind-in standart şəbəkəsi NetworkPolicy-ni tətbiq etmir, ona görə Calico qurulur. Müsahibədə bu detal çox soruşulur: "NetworkPolicy yazmaq kifayətdirmi?" — xeyr, CNI onu dəstəkləməlidir.

**5. Secret idarəetməsi**
Redis parolu deploy zamanı təsadüfi yaranır, Git-ə düşmür, environment variable kimi yox, fayl kimi qoşulur (env dəyişənləri loglara və crash dump-lara düşə bilər).

**6. Falco (runtime)**
Pod işləyəndə baş verənlərə baxır. Öz qaydalarımız: pod-da shell açılması, paket menecerinin işə düşməsi, Redis-dən xaricə bağlantı. Test API pod-unda shell açır və alertin gəldiyini yoxlayır. Qaydalar MITRE ATT&CK texnikalarına bağlanıb (T1059 və s.).

**7. kube-bench (CIS)**
Node və control-plane konfiqurasiyasını CIS standartına görə yoxlayır. Kind-də bəzi yoxlamalar gözlənilən şəkildə düşür; EKS-də control-plane-i AWS idarə edir.

**8. Terraform (EKS)**
Real AWS mühiti kod kimi yazılıb, amma pul getməsin deyə tətbiq edilmir; CI-da `validate` və Checkov ilə yoxlanılır. Ən vacib detallar: node-lar private subnet-də, secret-lər KMS ilə şifrələnir, IMDSv2 məcburidir (pod node-un IAM açarını oğurlaya bilmir), modullar tag-a yox commit SHA-ya bağlanıb (supply chain).

## Ehtimal olunan suallar

- **Niyə AWS-də real qurmadın?** Xərc. Amma Terraform kodu validate və təhlükəsizlik skanından keçir, eyni manifestlər EKS-də dəyişmədən işləyir (VPC CNI network policy dəstəyi açıqdır).
- **Falco niyə restricted namespace-də deyil?** Syscall-ları izləmək üçün kernel-ə çıxış lazımdır. Bu, sənədləşdirilmiş və bilərəkdən edilmiş istisnadır.
- **Image-lər niyə digest ilə pin olunmayıb?** Tag ilə pinlənib; növbəti addım Renovate ilə digest. Bunu README-də açıq yazmışam.
- **Policy-lərdə tapdığın bug nə idi?** Rego-da olmayan sahə ilə `!=` müqayisəsi "undefined" olur və qayda işləmir. Sahəni silən test bunu üzə çıxardı.
