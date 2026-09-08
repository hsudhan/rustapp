use serde::{Deserialize, Serialize};

use crate::error::AppError;

pub const DEFAULT_PAGE: u64 = 1;
pub const DEFAULT_PAGE_SIZE: u64 = 100;
pub const MAX_PAGE_SIZE: u64 = 100;

/// Raw query parameters for paginated endpoints.
#[derive(Debug, Default, Deserialize)]
pub struct PageParams {
    pub page: Option<u64>,
    pub page_size: Option<u64>,
}

impl PageParams {
    /// Apply defaults and enforce bounds.
    ///
    /// # Errors
    /// Returns `AppError::InvalidPagination` when `page` is 0 or
    /// `page_size` is outside `1..=MAX_PAGE_SIZE`.
    pub fn validate(self) -> Result<ValidatedPage, AppError> {
        let page = self.page.unwrap_or(DEFAULT_PAGE);
        let page_size = self.page_size.unwrap_or(DEFAULT_PAGE_SIZE);
        if page == 0 {
            return Err(AppError::InvalidPagination(
                "page must be greater than or equal to 1".to_owned(),
            ));
        }
        if page_size == 0 || page_size > MAX_PAGE_SIZE {
            return Err(AppError::InvalidPagination(format!(
                "page_size must be between 1 and {MAX_PAGE_SIZE}"
            )));
        }
        Ok(ValidatedPage { page, page_size })
    }
}

/// Pagination values that have passed validation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ValidatedPage {
    pub page: u64,
    pub page_size: u64,
}

impl ValidatedPage {
    #[must_use]
    pub fn limit(&self) -> i64 {
        i64::try_from(self.page_size).unwrap_or(i64::MAX)
    }

    #[must_use]
    pub fn offset(&self) -> i64 {
        let offset = (self.page - 1).saturating_mul(self.page_size);
        i64::try_from(offset).unwrap_or(i64::MAX)
    }
}

/// Pagination metadata block of the response envelope.
#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct PageMeta {
    pub page: u64,
    pub page_size: u64,
    pub total_records: u64,
    pub total_pages: u64,
}

/// Standard paginated response envelope.
#[derive(Debug, Serialize)]
pub struct Page<T> {
    pub data: Vec<T>,
    pub pagination: PageMeta,
}

impl<T> Page<T> {
    #[must_use]
    pub fn new(data: Vec<T>, page: ValidatedPage, total_records: u64) -> Self {
        Self {
            data,
            pagination: PageMeta {
                page: page.page,
                page_size: page.page_size,
                total_records,
                total_pages: total_records.div_ceil(page.page_size),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_applied() {
        let page = PageParams::default().validate().unwrap();
        assert_eq!(
            page,
            ValidatedPage {
                page: 1,
                page_size: 100
            }
        );
    }

    #[test]
    fn page_zero_is_rejected() {
        let err = PageParams {
            page: Some(0),
            page_size: None,
        }
        .validate()
        .unwrap_err();
        assert!(matches!(err, AppError::InvalidPagination(_)));
    }

    #[test]
    fn page_size_zero_is_rejected() {
        let result = PageParams {
            page: None,
            page_size: Some(0),
        }
        .validate();
        assert!(result.is_err());
    }

    #[test]
    fn page_size_above_max_is_rejected() {
        let result = PageParams {
            page: None,
            page_size: Some(101),
        }
        .validate();
        assert!(result.is_err());
    }

    #[test]
    fn page_size_at_max_is_accepted() {
        let page = PageParams {
            page: Some(3),
            page_size: Some(100),
        }
        .validate()
        .unwrap();
        assert_eq!(page.limit(), 100);
        assert_eq!(page.offset(), 200);
    }

    #[test]
    fn total_pages_rounds_up() {
        let page = PageParams {
            page: Some(1),
            page_size: Some(100),
        }
        .validate()
        .unwrap();
        let p: Page<()> = Page::new(vec![], page, 801);
        assert_eq!(p.pagination.total_pages, 9);
        let p: Page<()> = Page::new(vec![], page, 1000);
        assert_eq!(p.pagination.total_pages, 10);
        let p: Page<()> = Page::new(vec![], page, 0);
        assert_eq!(p.pagination.total_pages, 0);
    }

    #[test]
    fn huge_page_does_not_overflow() {
        let page = PageParams {
            page: Some(u64::MAX),
            page_size: Some(100),
        }
        .validate()
        .unwrap();
        assert_eq!(page.offset(), i64::MAX);
    }
}
